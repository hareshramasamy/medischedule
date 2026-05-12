# MediSchedule

A PostgreSQL-native healthcare scheduling and billing system.

## Stack
- **Backend**: PostgreSQL 17 on Supabase — all business logic in the database
- **Frontend**: React + Vite

## PostgreSQL features demonstrated
- Table partitioning (appointments, audit_log)
- Exclusion constraints with btree_gist (double-booking prevention)
- Trigger functions (audit log, state machine, record versioning, waitlist notification)
- PL/pgSQL functions (book_appointment, complete_appointment, search_patients, get_available_slots)
- Window functions & recursive CTEs (analytics views)
- Materialized views (doctor utilization dashboard)
- Full-text search with tsvector + pg_trgm fuzzy fallback
- JSONB with GIN indexes
- Generated columns, custom domains, composite types

## Setup

### Database
1. Create a Supabase project
2. Run `sql/medischedule.sql` in the SQL editor

### UI
```bash
cd ui
cp .env.example .env
# Add your Supabase URL and anon key to .env
npm install
npm run dev
```
