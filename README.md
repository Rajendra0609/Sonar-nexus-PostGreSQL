# SonarQube and Nexus Docker Setup

This project provides a Docker Compose configuration to set up a complete DevOps environment with SonarQube for code quality analysis and Nexus for artifact repository management.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              USERS (HTTP)                                    │
│                                    │                                         │
└────────────────────────────────────┼────────────────────────────────────────┘
                                     │
                                     ▼
┌───────────────────────────────────────────────────────────────────────────────┐
│                         jenkins bridge network                               │
│  ┌──────────────────────────┐  ┌──────────────────────────┐                 │
│  │      SonarQube           │  │       Nexus 3           │                 │
│  │  ┌────────────────────┐  │  │  ┌────────────────────┐  │                 │
│  │  │ sonarqube:8.9     │  │  │  │ sonatype/nexus3    │  │                 │
│  │  │ Port: 9000        │◄─┼──┼─►│ Port: 8081         │  │                 │
│  │  │ RAM: 1GB          │  │  │  │ RAM: 1GB           │  │                 │
│  │  │ CPU: 0.5          │  │  │  │ CPU: 0.5           │  │                 │
│  │  └────────┬───────────┘  │  │  └────────────────────┘  │                 │
│  │           │ JDBC          │  │                          │                 │
│  └───────────┼───────────────┘  └──────────────────────────┘                 │
│              │                                                               │
│              ▼                                                               │
│  ┌──────────────────────────┐                                                │
│  │      PostgreSQL          │                                                │
│  │  ┌────────────────────┐  │                                                │
│  │  │ postgres:15       │  │                                                │
│  │  │ Port: 5432        │  │                                                │
│  │  │ RAM: 1GB          │  │                                                │
│  │  │ CPU: 0.5          │  │                                                │
│  │  └────────────────────┘  │                                                │
│  └──────────────────────────┘                                                │
└───────────────────────────────────────────────────────────────────────────────┘
```

## Services

### 1. PostgreSQL
- **Image**: `postgres:15`
- **Container Name**: `postgres_sonar`
- **Purpose**: Database for SonarQube
- **Port**: `5432`
- **Resources**:
  - Memory: 1GB limit, 3GB swap
  - CPU: 0.5 cores

### 2. SonarQube
- **Image**: `sonarqube:8.9-community`
- **Container Name**: `sonarqube`
- **Purpose**: Code quality and security scanning platform
- **Port**: `9000`
- **Resources**:
  - Memory: 1GB limit, 3GB swap
  - CPU: 0.5 cores
- **Dependencies**: PostgreSQL

### 3. Nexus Repository
- **Image**: `sonatype/nexus3`
- **Container Name**: `nexus`
- **Purpose**: Artifact repository manager
- **Port**: `8081`
- **Resources**:
  - Memory: 1GB limit, 3GB swap
  - CPU: 0.5 cores

## Prerequisites

- Docker Engine 19.03.0+
- Docker Compose 1.29.0+
- At least 4GB of available RAM

## Environment Variables

Create a `.env` file in the same directory with the following variables:

```
env
POSTGRES_DB=sonar
POSTGRES_USER=sonar
POSTGRES_PASSWORD=your_secure_password
POSTGRES_JDBC_URL=jdbc:postgresql://postgres:5432/sonar
SONAR_WEB_JVM_OPTS=-Xmx512m -Xms512m
SONAR_CE_JVM_OPTS=-Xmx512m -Xms512m
SONAR_SEARCH_JVM_OPTS=-Xmx512m -Xms512m
```

## Quick Start

1. Clone the repository and navigate to the project directory:
   
```
bash
   cd sonar_right_work
   
```

2. Create the `.env` file with your configuration

3. Start all services:
   
```
bash
   docker-compose up -d
   
```

4. Wait for services to be healthy (approximately 2-3 minutes):
   
```
bash
   docker-compose ps
   
```

## Accessing Services

| Service | URL | Default Credentials |
|---------|-----|---------------------|
| SonarQube | http://localhost:9000 | admin / admin |
| Nexus | http://localhost:8081 | admin / admin123 |

## Volume Mounts

- **PostgreSQL Data**: `./postgres/data` → `/var/lib/postgresql/data`
- **Nexus Data**: Named volume `nexus-data`
- **SonarQube Data**: Named volume `sonarqube_data_all`

## Network

All services are connected via the `jenkins` bridge network for inter-container communication.

## Security Features

- SonarQube runs as non-root user (UID: 1000)
- Root filesystem is read-only
- Linux capabilities are dropped
- No new privileges allowed
- Temp filesystem for temporary files

## Health Checks

Each service includes health checks:
- **PostgreSQL**: `pg_isready` check every 30s
- **SonarQube**: HTTP check on port 9000 every 30s
- **Nexus**: REST API status check every 30s

## Stopping Services

```
bash
docker-compose down
```

To remove all data volumes:
```
bash
docker-compose down -v
```

## Troubleshooting

### SonarQube not starting
- Ensure at least 1GB of memory is available
- Check logs: `docker-compose logs sonarqube`

### Nexus initialization takes time
- Initial setup can take up to 2 minutes
- Check logs: `docker-compose logs nexus`

### Database connection issues
- Verify PostgreSQL is healthy: `docker-compose ps`
- Check credentials in `.env` file

