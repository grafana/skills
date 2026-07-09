# Object-storage backends

## S3

```yaml
blocks_storage:
  backend: s3
  s3:
    bucket_name: mimir-blocks
    endpoint: s3.us-east-1.amazonaws.com
    region: us-east-1
    access_key_id: ${AWS_ACCESS_KEY_ID}
    secret_access_key: ${AWS_SECRET_ACCESS_KEY}
```

## GCS

```yaml
blocks_storage:
  backend: gcs
  gcs:
    bucket_name: mimir-blocks
```

## Azure Blob

```yaml
blocks_storage:
  backend: azure
  azure:
    account_name: storageaccountname
    account_key: ${AZURE_STORAGE_KEY}
    container_name: mimir-blocks
```

## Filesystem (dev / single-node only)

```yaml
blocks_storage:
  backend: filesystem
  filesystem:
    dir: /tmp/mimir/data/tsdb
```
