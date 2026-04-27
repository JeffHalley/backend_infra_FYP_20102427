# Backend Infrastructure - FYP (20102427)

A fully serverless, AI-powered backend deployed on AWS using Terraform. Built as a Final Year Project, this system exposes a natural-language query interface over a PostgreSQL database via an AWS Bedrock Agent, secured behind Cognito authentication and an HTTP API Gateway.

---

## Architecture Overview

```
Client (React / CloudFront)
        │
        ▼
API Gateway (HTTP API)
  JWT Auth via Cognito
        │
        ▼
Lambda: api_handler  ──────────────────────────────────────────────┐
  (bedrock-sql-api-handler)                                         │
        │                                                           │
        ▼                                                           │
AWS Bedrock Agent (sql-data-agent)                        DynamoDB: conversations
  Model: claude-sonnet-4-5                                (session history + TTL)
        │
        ▼
Lambda: db_conn
  (bedrock-sql-db-conn)
        │
        ▼
EC2 Spot Instance (t4g.small)
  PostgreSQL 16
```

---

## Services & Components

### AWS Bedrock Agent
- Agent name: `sql-data-agent`
- Foundation model: `eu.anthropic.claude-sonnet-4-5-20250929-v1:0`
- Accepts natural-language queries and translates them to SQL via a custom action group (`postgress_query_group`)
- Instruction prompt loaded dynamically from `prompt.txt`, targeting the `public.metrics` table
- Session TTL: 3600 seconds

### API Gateway (HTTP API)
- Name: `bedrock-gateway`
- Routes:
  - `POST /ask` - submit a natural-language query
  - `GET /conversations` - retrieve conversation history
  - `POST /conversations` - create a new conversation session
- All routes protected by JWT authoriser (Cognito)
- Access logs sent to CloudWatch (7-day retention)

### Lambda Functions

| Function | Name | Purpose |
|---|---|---|
| `api_handler` | `bedrock-sql-api-handler` | Main entry point; routes requests to Bedrock agent |
| `db_conn` | `bedrock-sql-db-conn` | Executes SQL queries against PostgreSQL on behalf of the agent |

Both functions run Python 3.12, are deployed inside the default VPC, and use a shared Lambda security group.

### Authentication - Amazon Cognito
- User Pool: `chat-user-pool`
- Sign-up/login via email
- Supported auth flows: SRP, password, refresh token
- Callback URLs configured for both local dev (`localhost:5173`) and production (CloudFront)

### Database - PostgreSQL on EC2 Spot
- Instance type: `t4g.small` (ARM64, Amazon Linux 2023)
- Market type: persistent spot instance
- PostgreSQL 16 installed and configured via EC2 user data
- Accessible only from the Lambda security group on port 5432
- 30 GB gp3 root volume
- Read-only Lambda user: `lambda_reader`

### DynamoDB - Conversation Store
- Table: `conversations`
- Composite key: `userId` (hash) + `sessionId` (range)
- Billing: pay-per-request

### SES
- Configured via `ses.tf` (email sending for alerts or notifications)

### IAM
- Dedicated roles for the Bedrock agent (`bedrock_agent_role`) and Lambda functions (`lambda_role`)
- Bedrock granted `lambda:InvokeFunction` permission on the DB Lambda
- API Gateway granted `lambda:InvokeFunction` permission on the API handler Lambda

---

## Repository Structure

```
.
├── agent.tf                   # Bedrock Agent + action group
├── api_gateway.tf             # HTTP API Gateway, routes, authoriser, logging
├── auth.tf                    # Cognito user pool + DynamoDB conversations table
├── ec2.tf                     # Spot EC2 instance running PostgreSQL
├── iam.tf                     # IAM roles and policies
├── lambda.tf                  # Lambda functions + packaging
├── outputs.tf                 # Terraform outputs
├── provider.tf                # AWS provider configuration
├── ses.tf                     # SES configuration
├── vpc.tf                     # VPC / networking
├── prompt.txt                 # Bedrock agent instruction prompt
├── FYP_openAPI_Final.yaml     # OpenAPI spec
├── Alert_Action_Group.yaml    # Bedrock action group schema for alerts
├── DB_Action_Group.yaml       # Bedrock action group schema for DB queries
├── lambdas/
│   └── index.py               # API handler Lambda source
├── db_lambda/
│   ├── db_conn.py             # DB connection Lambda source
│   └── utils.py               # DB utility helpers
├── alert_lambda/              # Alert Lambda source
└── cron_scripts_db_ec2/       # Cron scripts for DB maintenance on EC2
```

---

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/downloads) >= 1.14.3 with AWS provider >=6.0
- AWS CLI configured with appropriate credentials
- AWS account with Bedrock model access enabled for `eu.anthropic.claude-sonnet-4-5` in `eu-west-1` - enable via marketplace subscription
- An EC2 key pair already created in your AWS account

---

## Deployment

```bash
# Initialise Terraform
terraform init

# Preview the plan
terraform plan

# Deploy
terraform apply
```

> **Note:** Bedrock foundation model access must be requested and approved in the AWS console before deployment.

---

## API Reference

All endpoints require a valid Cognito JWT passed in the `Authorization` header.

| Method | Path | Description |
|---|---|---|
| `POST` | `/ask` | Send a natural-language question about the database |
| `GET` | `/conversations` | List conversation sessions for the authenticated user |
| `POST` | `/conversations` | Start a new conversation session |

See `FYP_openAPI_Final.yaml` for the full OpenAPI specification.

---

## Technologies

- **Infrastructure as Code:** Terraform (HCL)
- **Runtime:** Python 3.12
- **AI:** AWS Bedrock (Anthropic Claude Sonnet 4.5)
- **Auth:** Amazon Cognito
- **API:** Amazon API Gateway v2 (HTTP)
- **Compute:** AWS Lambda, EC2 Spot
- **Database:** PostgreSQL 16
- **Storage:** DynamoDB, S3 (implicit via Lambda packaging)
- **Observability:** CloudWatch Logs
- **Email:** Amazon SES
