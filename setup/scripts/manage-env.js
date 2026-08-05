const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const ROOT_DIR = path.resolve(__dirname, '../../');
const DEFAULT_ENV_PATH = path.join(ROOT_DIR, '.env');
const DEFAULT_ENV_EXAMPLE_PATH = path.join(ROOT_DIR, '.env.example');
const BACKUP_DIR = path.join(ROOT_DIR, 'setup', 'backups');

const forceMode = process.argv.includes('--force');
const positionalArgs = process.argv.slice(2).filter(a => !a.startsWith('--'));
const targetEnvPath = positionalArgs[0] ? path.resolve(positionalArgs[0]) : DEFAULT_ENV_PATH;
const targetEnvExamplePath = positionalArgs[1] ? path.resolve(positionalArgs[1]) : DEFAULT_ENV_EXAMPLE_PATH;

function generateSecurePassword(length = 24) {
    return crypto.randomBytes(length).toString('base64').replace(/[^a-zA-Z0-9]/g, '').slice(0, length);
}

// CRM_ENCRYPTION_KEY e' decodificado pelo evocrm_processor via Python
// cryptography.fernet.Fernet(), que exige base64 genuino de exatamente 32
// bytes brutos - generateSecurePassword() remove os caracteres especiais do
// base64 (+/=) e corta pra um tamanho fixo, o que NAO decodifica de volta
// em 32 bytes (erro real visto em producao: "Fernet key must be 32
// url-safe base64-encoded bytes"). Mesmo metodo que a doc do vendor indica
// ("openssl rand -base64 32") - sem strip de caracteres.
function generateFernetKey() {
    return crypto.randomBytes(32).toString('base64');
}

function generateUUID() {
    return crypto.randomUUID();
}

const MAX_BACKUPS_PER_TARGET = 10;

function pruneOldBackups(targetBaseName) {
    const backupPrefix = `env_bkp_${targetBaseName}_`;
    const backups = fs.readdirSync(BACKUP_DIR)
        .filter(f => f.startsWith(backupPrefix) && f.endsWith('.env'))
        .sort();

    const excess = backups.length - MAX_BACKUPS_PER_TARGET;
    if (excess > 0) {
        for (const file of backups.slice(0, excess)) {
            fs.unlinkSync(path.join(BACKUP_DIR, file));
            console.log(`🗑️  [Setup ENV] Backup antigo removido: setup/backups/${file}`);
        }
    }
}

function getFormattedDate() {
    const now = new Date();
    const year = now.getFullYear();
    const month = String(now.getMonth() + 1).padStart(2, '0');
    const day = String(now.getDate()).padStart(2, '0');
    return `${year}-${month}-${day}`;
}

function parseEnv(content) {
    const env = {};
    const lines = content.split('\n');
    for (const line of lines) {
        const trimmed = line.trim();
        if (!trimmed || trimmed.startsWith('#')) continue;
        const eqIdx = trimmed.indexOf('=');
        if (eqIdx !== -1) {
            const key = trimmed.slice(0, eqIdx).trim();
            const value = trimmed.slice(eqIdx + 1).trim();
            env[key] = value;
        }
    }
    return env;
}

function isSecretKey(key) {
    const uppercaseKey = key.toUpperCase();
    const secretKeywords = ['PASSWORD', 'PASS', 'SECRET', 'KEY', 'TOKEN', 'AUTH'];
    return secretKeywords.some(keyword => uppercaseKey.includes(keyword));
}

function resolveVariables(content, sourceEnv) {
    return content.replace(/\$\{([^}]+)\}/g, (match, varName) => {
        return sourceEnv[varName] !== undefined ? sourceEnv[varName] : match;
    });
}

// Quando o .env JA EXISTE, o resto do script so' itera as linhas que ja
// estao nele - uma chave nova adicionada ao .env.example depois que o .env
// de um cliente ja foi gerado NUNCA seria criada nele (nem vazia, pra depois
// ser preenchida com senha aleatoria). Isso ja causou um bug real: chaves
// novas (ex: segredos do EvoCRM) ficaram permanentemente ausentes de um
// .env real, mesmo apos multiplas execucoes. Reconcilia aqui, antes da
// geracao de senha, para que chaves novas apareçam com o default do
// template (ou vazias, se forem secretas - aí a passada de geracao logo
// abaixo ja preenche na mesma execucao).
function reconcileMissingKeys(envContent, examplePath) {
    if (!fs.existsSync(examplePath)) {
        return envContent;
    }

    const currentEnv = parseEnv(envContent);
    const exampleEnv = parseEnv(fs.readFileSync(examplePath, 'utf-8'));
    const missingKeys = Object.keys(exampleEnv).filter(key => !(key in currentEnv));

    if (missingKeys.length === 0) {
        return envContent;
    }

    console.log(`🔄 [Setup ENV] ${missingKeys.length} chave(s) nova(s) do template ausente(s) no .env atual - adicionando: ${missingKeys.join(', ')}`);

    let updated = envContent.endsWith('\n') ? envContent : envContent + '\n';
    updated += '\n# --- Chaves reconciliadas automaticamente a partir do template ---\n';
    for (const key of missingKeys) {
        updated += `${key}=${exampleEnv[key]}\n`;
    }
    return updated;
}

function main() {
    console.log(`🚀 [Setup ENV] Processando arquivo de ambiente: ${targetEnvPath}`);

    if (!fs.existsSync(BACKUP_DIR)) {
        fs.mkdirSync(BACKUP_DIR, { recursive: true });
    }

    let envContent = '';
    let isNewFile = false;

    if (!fs.existsSync(targetEnvPath)) {
        if (!fs.existsSync(targetEnvExamplePath)) {
            console.error(`❌ Arquivo exemplo nao encontrado em: ${targetEnvExamplePath}`);
            process.exit(1);
        }

        const targetBaseName = path.basename(targetEnvPath, '.env');
        const backupPrefix = `env_bkp_${targetBaseName}_`;
        const existingBackups = fs.existsSync(BACKUP_DIR)
            ? fs.readdirSync(BACKUP_DIR).filter(f => f.startsWith(backupPrefix) && f.endsWith('.env')).sort()
            : [];

        if (existingBackups.length > 0 && !forceMode) {
            const latestBackup = existingBackups[existingBackups.length - 1];
            console.error('');
            console.error(`⚠️  ATENCAO: "${path.basename(targetEnvPath)}" nao encontrado, mas existem ${existingBackups.length} backup(s) anterior(es).`);
            console.error(`   Gerar novas senhas NAO atualizara bancos ja inicializados (MongoDB, PostgreSQL, RabbitMQ).`);
            console.error(`   Os volumes Docker preservam as senhas originais da primeira inicializacao.`);
            console.error('');
            console.error(`   Para restaurar as credenciais anteriores:`);
            console.error(`     cp setup/backups/${latestBackup} ${path.relative(ROOT_DIR, targetEnvPath)}`);
            console.error('');
            console.error(`   Para forcar geracao de novas senhas (requer recriar volumes):`);
            console.error(`     node setup/scripts/manage-env.js --force`);
            console.error('');
            process.exit(1);
        }

        if (existingBackups.length > 0 && forceMode) {
            console.warn(`⚠️  --force: gerando novas senhas. Volumes dos bancos precisam ser recriados.`);
        }

        console.log(`📄 Criando novo arquivo .env a partir do template: ${targetEnvExamplePath}`);
        envContent = fs.readFileSync(targetEnvExamplePath, 'utf-8');
        isNewFile = true;
    } else {
        envContent = fs.readFileSync(targetEnvPath, 'utf-8');
    }

    const currentEnv = parseEnv(envContent);

    const hasExistingPasswords = Object.keys(currentEnv).some(key => isSecretKey(key) && currentEnv[key] && currentEnv[key].length > 0);

    if (!isNewFile && hasExistingPasswords) {
        const targetFileName = path.basename(targetEnvPath, '.env');
        const backupFileName = `env_bkp_${targetFileName}_${getFormattedDate()}_${generateUUID()}.env`;
        const backupPath = path.join(BACKUP_DIR, backupFileName);
        fs.writeFileSync(backupPath, envContent, 'utf-8');
        console.log(`📦 Backup do .env existente salvo em: setup/backups/${backupFileName}`);
        pruneOldBackups(targetFileName);
    }

    if (!isNewFile) {
        envContent = reconcileMissingKeys(envContent, targetEnvExamplePath);
    }

    const rootEnvPath = path.join(ROOT_DIR, '.env');
    if (fs.existsSync(rootEnvPath) && path.resolve(targetEnvPath) !== path.resolve(rootEnvPath)) {
        const rootEnv = parseEnv(fs.readFileSync(rootEnvPath, 'utf-8'));
        const unresolvedCount = (envContent.match(/\$\{[^}]+\}/g) || []).length;
        if (unresolvedCount > 0) {
            envContent = resolveVariables(envContent, rootEnv);
            const remainingCount = (envContent.match(/\$\{[^}]+\}/g) || []).length;
            const resolvedCount = unresolvedCount - remainingCount;
            console.log(`🔗 [Setup ENV] ${resolvedCount} variavel(is) resolvida(s) a partir do .env raiz.`);
            if (remainingCount > 0) {
                console.warn(`⚠️ [Setup ENV] ${remainingCount} variavel(is) nao resolvida(s) — chave(s) ausente(s) no .env raiz.`);
            }
        }
    }

    let updatedLines = envContent.split('\n');
    let generatedCount = 0;

    updatedLines = updatedLines.map(line => {
        const trimmed = line.trim();
        if (!trimmed || trimmed.startsWith('#')) return line;
        
        const eqIdx = trimmed.indexOf('=');
        if (eqIdx === -1) return line;

        const key = trimmed.slice(0, eqIdx).trim();
        const currentValue = trimmed.slice(eqIdx + 1).trim();

        if (isSecretKey(key) && (!currentValue || currentValue === '')) {
            let newPassword;
            if (key === 'CRM_ENCRYPTION_KEY') {
                newPassword = generateFernetKey();
            } else {
                const length = (key.includes('KEY') || key.includes('SECRET')) ? 32 : 24;
                newPassword = generateSecurePassword(length);
            }
            generatedCount++;
            return `${key}=${newPassword}`;
        }

        return line;
    });

    fs.writeFileSync(targetEnvPath, updatedLines.join('\n'), 'utf-8');

    if (generatedCount > 0) {
        console.log(`✅ [Setup ENV] ${generatedCount} variáveis seguras geradas com sucesso!`);
    } else {
        console.log('ℹ️ [Setup ENV] Todas as variáveis de senha/segurança já estavam preenchidas.');
    }
}

main();
