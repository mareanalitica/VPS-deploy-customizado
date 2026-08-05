CLIENT ?=

.PHONY: client-scaffold client-plan client-new client-configure client-destroy

client-scaffold:
	@test -n "$(CLIENT)" || (echo "uso: make client-scaffold CLIENT=<nome>" && exit 1)
	cp -r infra/terraform/clients/_template infra/terraform/clients/$(CLIENT)
	@echo "Preencha infra/terraform/clients/$(CLIENT)/terraform.tfvars e backend.tf (a partir dos .example) antes de 'make client-plan'."

client-plan:
	@test -n "$(CLIENT)" || (echo "uso: make client-plan CLIENT=<nome>" && exit 1)
	cd infra/terraform/clients/$(CLIENT) && terraform init && terraform plan

client-new:
	@test -n "$(CLIENT)" || (echo "uso: make client-new CLIENT=<nome>" && exit 1)
	cd infra/terraform/clients/$(CLIENT) && terraform init && terraform apply
	$(MAKE) client-configure CLIENT=$(CLIENT)

client-configure:
	@test -n "$(CLIENT)" || (echo "uso: make client-configure CLIENT=<nome>" && exit 1)
	cd infra/ansible && ansible-playbook site.yml --limit $(CLIENT)

client-destroy:
	@test -n "$(CLIENT)" || (echo "uso: make client-destroy CLIENT=<nome>" && exit 1)
	@echo "lifecycle.prevent_destroy protege o recurso do servidor - ver infra/terraform/README.md#decomissionando-um-cliente"
	cd infra/terraform/clients/$(CLIENT) && terraform destroy
