USE cinder;

-- 1. Soft delete the volume
UPDATE volumes SET deleted=1, status='deleted', terminated_at=NOW(), deleted_at=NOW() 
WHERE id='0bea5e24-6609-4aab-b928-db33b397b983';

-- 2. Clean up any remaining volume_admin_metadata
UPDATE volume_admin_metadata SET deleted=1, deleted_at=NOW() 
WHERE volume_id='0bea5e24-6609-4aab-b928-db33b397b983';

-- 3. Clean up volume_glance_metadata (since it's an image-backed volume)
UPDATE volume_glance_metadata SET deleted=1, deleted_at=NOW() 
WHERE volume_id='0bea5e24-6609-4aab-b928-db33b397b983';





kolla-ansible -i ./multinode reconfigure \
  --tags cinder \
  -e @/etc/kolla/config/cinder/vault.yml \
  --ask-vault-pass




kolla-ansible deploy  -i ./multinode --configdir ./etc/kolla --tags rabbitmq  -e @ansible/secrets.yaml --vault-password-file ./ansible/.vault_pass
