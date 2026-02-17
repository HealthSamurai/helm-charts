# postgres

[PostgreSQL](https://www.postgresql.org/)

![Version: 0.0.2](https://img.shields.io/badge/Version-0.0.2-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 18](https://img.shields.io/badge/AppVersion-18-informational?style=flat-square)

```console
helm repo add health-samurai https://healthsamurai.github.io/helm-charts
```

```console
helm upgrade --install postgres health-samurai/postgres --values /path/to/config/file
```

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| affinity | object | `{}` |  |
| config | string | `"# pg_stat_statements.max = 500\n# pg_stat_statements.save = false\n# pg_stat_statements.track = top\n# pg_stat_statements.track_utility = true\n# shared_preload_libraries = 'pg_stat_statements'\n#\n# wal_level = logical\n# wal_log_hints = on\n#\n# archive_mode = on\n#\n# Set WAL shipping with WAL-G to storage defined by env with WALG_ prefix\n# archive_command = 'wal-g wal-push %p'\n# restore_command = 'wal-g wal-fetch %f %p'"` |  |
| dataVolumeMountPath | string | `"/data"` |  |
| env.PGDATA | string | `"/data/pg"` |  |
| env.POSTGRES_DB | string | `"postgres"` |  |
| env.POSTGRES_PASSWORD | string | `"postgres"` |  |
| env.POSTGRES_USER | string | `"postgres"` |  |
| extraEnvFromSecrets | list | `[]` |  |
| fullnameOverride | string | `""` |  |
| image.pullPolicy | string | `"IfNotPresent"` |  |
| image.repository | string | `"postgres"` |  |
| image.tag | string | `""` |  |
| imagePullSecrets | list | `[]` |  |
| livenessProbe.exec.command[0] | string | `"/bin/sh"` |  |
| livenessProbe.exec.command[1] | string | `"-c"` |  |
| livenessProbe.exec.command[2] | string | `"exec pg_isready -U $POSTGRES_USER -h 127.0.0.1 -p 5432"` |  |
| livenessProbe.failureThreshold | int | `6` |  |
| livenessProbe.initialDelaySeconds | int | `30` |  |
| livenessProbe.periodSeconds | int | `10` |  |
| livenessProbe.successThreshold | int | `1` |  |
| livenessProbe.timeoutSeconds | int | `5` |  |
| nameOverride | string | `""` |  |
| nodeSelector | object | `{}` |  |
| podAnnotations | object | `{}` |  |
| podLabels | object | `{}` |  |
| podSecurityContext | object | `{}` |  |
| readinessProbe.exec.command[0] | string | `"/bin/sh"` |  |
| readinessProbe.exec.command[1] | string | `"-c"` |  |
| readinessProbe.exec.command[2] | string | `"-e"` |  |
| readinessProbe.exec.command[3] | string | `"exec pg_isready -U $POSTGRES_USER -h 127.0.0.1 -p 5432"` |  |
| readinessProbe.failureThreshold | int | `6` |  |
| readinessProbe.initialDelaySeconds | int | `5` |  |
| readinessProbe.periodSeconds | int | `10` |  |
| readinessProbe.successThreshold | int | `1` |  |
| readinessProbe.timeoutSeconds | int | `5` |  |
| resources | object | `{}` |  |
| securityContext | object | `{}` |  |
| service.port | int | `5432` |  |
| service.type | string | `"ClusterIP"` |  |
| serviceAccount.annotations | object | `{}` |  |
| serviceAccount.automount | bool | `true` |  |
| serviceAccount.create | bool | `true` |  |
| serviceAccount.name | string | `""` |  |
| storage.attach | bool | `true` |  |
| storage.className | string | `""` |  |
| storage.size | string | `"10Gi"` |  |
| tolerations | list | `[]` |  |
| volumeMounts | list | `[]` |  |
| volumes | list | `[]` |  |
| walg.enabled | bool | `false` |  |
| walg.image.repository | string | `"healthsamurai/wal-g"` |  |
| walg.image.tag | string | `"v3.0.5"` |  |
