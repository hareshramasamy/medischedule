-- =============================================================================
-- MediSchedule: Schema — Extensions, Domains, Types, Tables, Indexes
-- =============================================================================
-- All objects in public schema — compatible with Supabase REST API
-- Run order: 01 → 02 → 03 → 04 → 05 → 06 → 07
-- =============================================================================


-- =============================================================================
-- EXTENSIONS
-- =============================================================================

CREATE EXTENSION IF NOT EXISTS "pg_trgm";
CREATE EXTENSION IF NOT EXISTS "btree_gist";


-- =============================================================================
-- CUSTOM DOMAINS
-- =============================================================================

CREATE DOMAIN phone_number AS TEXT
    CHECK (VALUE ~ '^\+?[0-9\s\-\(\)]{7,20}$');

CREATE DOMAIN email_address AS TEXT
    CHECK (VALUE ~* '^[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}$');

CREATE DOMAIN positive_money AS NUMERIC(12, 2)
    CHECK (VALUE >= 0);

CREATE DOMAIN us_state AS CHAR(2)
    CHECK (VALUE ~ '^[A-Z]{2}$');


-- =============================================================================
-- CUSTOM TYPES
-- =============================================================================

CREATE TYPE appointment_status AS ENUM (
    'scheduled', 'confirmed', 'checked_in', 'in_progress',
    'completed', 'cancelled', 'no_show', 'rescheduled'
);

CREATE TYPE claim_status AS ENUM (
    'draft', 'submitted', 'acknowledged', 'pending_info',
    'approved', 'partially_approved', 'denied', 'appealed', 'paid'
);

CREATE TYPE user_role AS ENUM (
    'admin', 'doctor', 'nurse', 'receptionist', 'patient', 'billing_staff'
);

CREATE TYPE day_of_week AS ENUM (
    'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday'
);

CREATE TYPE address_t AS (
    street  TEXT,
    city    TEXT,
    state   us_state,
    zip     TEXT,
    country TEXT
);


-- =============================================================================
-- TABLES
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Users
-- ---------------------------------------------------------------------------
CREATE TABLE users (
    user_id       UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    email         email_address NOT NULL UNIQUE,
    full_name     TEXT          NOT NULL,
    role          user_role     NOT NULL,
    password_hash TEXT          NOT NULL,
    is_active     BOOLEAN       NOT NULL DEFAULT TRUE,
    last_login_at TIMESTAMPTZ,
    created_at    TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_users_role  ON users(role);
CREATE INDEX idx_users_email ON users(email);


-- ---------------------------------------------------------------------------
-- Departments
-- ---------------------------------------------------------------------------
CREATE TABLE departments (
    dept_id        SERIAL PRIMARY KEY,
    name           TEXT NOT NULL,
    parent_dept_id INT  REFERENCES departments(dept_id),
    head_user_id   UUID REFERENCES users(user_id),
    created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_departments_parent ON departments(parent_dept_id);


-- ---------------------------------------------------------------------------
-- Doctors
-- ---------------------------------------------------------------------------
CREATE TABLE doctors (
    doctor_id        UUID           PRIMARY KEY REFERENCES users(user_id),
    dept_id          INT            NOT NULL REFERENCES departments(dept_id),
    specialty        TEXT           NOT NULL,
    license_number   TEXT           NOT NULL UNIQUE,
    npi_number       TEXT           UNIQUE,
    consultation_fee positive_money NOT NULL,
    bio              TEXT,
    metadata         JSONB          NOT NULL DEFAULT '{}',
    search_vector    TSVECTOR,
    created_at       TIMESTAMPTZ    NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_doctors_dept      ON doctors(dept_id);
CREATE INDEX idx_doctors_specialty ON doctors(specialty);
CREATE INDEX idx_doctors_metadata  ON doctors USING GIN(metadata);
CREATE INDEX idx_doctors_search    ON doctors USING GIN(search_vector);


-- ---------------------------------------------------------------------------
-- Patients
-- ---------------------------------------------------------------------------
CREATE TABLE patients (
    patient_id         UUID           PRIMARY KEY REFERENCES users(user_id),
    date_of_birth      DATE           NOT NULL,
    gender             TEXT,
    address            address_t,
    phone              phone_number,
    emergency_contact  JSONB,
    blood_type         TEXT,
    allergies          TEXT[],
    insurance_provider TEXT,
    insurance_id       TEXT,
    metadata           JSONB          NOT NULL DEFAULT '{}',
    search_vector      TSVECTOR,
    created_at         TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    updated_at         TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_dob CHECK (date_of_birth < CURRENT_DATE)
);

CREATE INDEX idx_patients_name_search ON patients USING GIN(search_vector);
CREATE INDEX idx_patients_insurance   ON patients(insurance_provider, insurance_id);
CREATE INDEX idx_patients_metadata    ON patients USING GIN(metadata);
CREATE INDEX idx_patients_allergies   ON patients USING GIN(allergies);


-- ---------------------------------------------------------------------------
-- Rooms
-- ---------------------------------------------------------------------------
CREATE TABLE rooms (
    room_id     SERIAL  PRIMARY KEY,
    room_number TEXT    NOT NULL UNIQUE,
    room_type   TEXT    NOT NULL,
    dept_id     INT     REFERENCES departments(dept_id),
    capacity    INT     NOT NULL DEFAULT 1,
    is_active   BOOLEAN NOT NULL DEFAULT TRUE,
    equipment   JSONB   NOT NULL DEFAULT '[]'
);


-- ---------------------------------------------------------------------------
-- Doctor Schedules
-- ---------------------------------------------------------------------------
CREATE TABLE doctor_schedules (
    schedule_id   SERIAL       PRIMARY KEY,
    doctor_id     UUID         NOT NULL REFERENCES doctors(doctor_id),
    day_of_week   day_of_week  NOT NULL,
    start_time    TIME         NOT NULL,
    end_time      TIME         NOT NULL,
    slot_duration INT          NOT NULL DEFAULT 30,
    is_active     BOOLEAN      NOT NULL DEFAULT TRUE,
    valid_from    DATE         NOT NULL DEFAULT CURRENT_DATE,
    valid_until   DATE,
    CONSTRAINT chk_schedule_times CHECK (start_time < end_time),
    CONSTRAINT chk_slot_duration  CHECK (slot_duration IN (15, 20, 30, 45, 60)),
    UNIQUE (doctor_id, day_of_week, valid_from)
);


-- ---------------------------------------------------------------------------
-- Schedule Exceptions
-- ---------------------------------------------------------------------------
CREATE TABLE schedule_exceptions (
    exception_id   SERIAL  PRIMARY KEY,
    doctor_id      UUID    NOT NULL REFERENCES doctors(doctor_id),
    exception_date DATE    NOT NULL,
    reason         TEXT,
    is_full_day    BOOLEAN NOT NULL DEFAULT TRUE,
    blocked_from   TIME,
    blocked_until  TIME,
    created_by     UUID    NOT NULL REFERENCES users(user_id),
    created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_partial_block CHECK (
        is_full_day = TRUE OR (blocked_from IS NOT NULL AND blocked_until IS NOT NULL)
    )
);

CREATE INDEX idx_exceptions_doctor_date ON schedule_exceptions(doctor_id, exception_date);


-- ---------------------------------------------------------------------------
-- Appointments (partitioned by quarter)
-- ---------------------------------------------------------------------------
CREATE TABLE appointments (
    appointment_id      UUID               NOT NULL DEFAULT gen_random_uuid(),
    patient_id          UUID               NOT NULL REFERENCES patients(patient_id),
    doctor_id           UUID               NOT NULL REFERENCES doctors(doctor_id),
    room_id             INT                REFERENCES rooms(room_id),
    scheduled_start     TIMESTAMPTZ        NOT NULL,
    scheduled_end       TIMESTAMPTZ        NOT NULL,
    actual_start        TIMESTAMPTZ,
    actual_end          TIMESTAMPTZ,
    status              appointment_status NOT NULL DEFAULT 'scheduled',
    appointment_type    TEXT               NOT NULL,
    chief_complaint     TEXT,
    notes               TEXT,
    metadata            JSONB              NOT NULL DEFAULT '{}',
    cancelled_by        UUID               REFERENCES users(user_id),
    cancellation_reason TEXT,
    created_by          UUID               NOT NULL REFERENCES users(user_id),
    created_at          TIMESTAMPTZ        NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ        NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_appt_times    CHECK (scheduled_start < scheduled_end),
    CONSTRAINT chk_actual_times  CHECK (actual_start IS NULL OR actual_start < actual_end),
    CONSTRAINT chk_cancel_reason CHECK (
        status NOT IN ('cancelled') OR cancellation_reason IS NOT NULL
    ),
    PRIMARY KEY (appointment_id, scheduled_start)
) PARTITION BY RANGE (scheduled_start);

CREATE TABLE appointments_2024_q1 PARTITION OF appointments FOR VALUES FROM ('2024-01-01') TO ('2024-04-01');
CREATE TABLE appointments_2024_q2 PARTITION OF appointments FOR VALUES FROM ('2024-04-01') TO ('2024-07-01');
CREATE TABLE appointments_2024_q3 PARTITION OF appointments FOR VALUES FROM ('2024-07-01') TO ('2024-10-01');
CREATE TABLE appointments_2024_q4 PARTITION OF appointments FOR VALUES FROM ('2024-10-01') TO ('2025-01-01');
CREATE TABLE appointments_2025_q1 PARTITION OF appointments FOR VALUES FROM ('2025-01-01') TO ('2025-04-01');
CREATE TABLE appointments_2025_q2 PARTITION OF appointments FOR VALUES FROM ('2025-04-01') TO ('2025-07-01');
CREATE TABLE appointments_2025_q3 PARTITION OF appointments FOR VALUES FROM ('2025-07-01') TO ('2025-10-01');
CREATE TABLE appointments_2025_q4 PARTITION OF appointments FOR VALUES FROM ('2025-10-01') TO ('2026-01-01');
CREATE TABLE appointments_2026_q1 PARTITION OF appointments FOR VALUES FROM ('2026-01-01') TO ('2026-04-01');
CREATE TABLE appointments_2026_q2 PARTITION OF appointments FOR VALUES FROM ('2026-04-01') TO ('2026-07-01');
CREATE TABLE appointments_2026_q3 PARTITION OF appointments FOR VALUES FROM ('2026-07-01') TO ('2026-10-01');
CREATE TABLE appointments_2026_q4 PARTITION OF appointments FOR VALUES FROM ('2026-10-01') TO ('2027-01-01');
CREATE TABLE appointments_default PARTITION OF appointments DEFAULT;

CREATE INDEX idx_appt_doctor_time ON appointments(doctor_id, scheduled_start, scheduled_end);
CREATE INDEX idx_appt_patient     ON appointments(patient_id, scheduled_start);
CREATE INDEX idx_appt_status      ON appointments(status) WHERE status NOT IN ('completed','cancelled');
CREATE INDEX idx_appt_room_time   ON appointments(room_id, scheduled_start, scheduled_end) WHERE room_id IS NOT NULL;


-- ---------------------------------------------------------------------------
-- Appointment Locks (exclusion constraint for double-booking prevention)
-- ---------------------------------------------------------------------------
CREATE TABLE appointment_locks (
    lock_id        SERIAL    PRIMARY KEY,
    doctor_id      UUID      NOT NULL,
    time_range     TSTZRANGE NOT NULL,
    appointment_id UUID      NOT NULL,
    EXCLUDE USING GIST (
        doctor_id  WITH =,
        time_range WITH &&
    )
);

CREATE TABLE room_locks (
    lock_id        SERIAL    PRIMARY KEY,
    room_id        INT       NOT NULL,
    time_range     TSTZRANGE NOT NULL,
    appointment_id UUID      NOT NULL,
    EXCLUDE USING GIST (
        room_id    WITH =,
        time_range WITH &&
    )
);


-- ---------------------------------------------------------------------------
-- Waitlist
-- ---------------------------------------------------------------------------
CREATE TABLE waitlist (
    waitlist_id              SERIAL  PRIMARY KEY,
    patient_id               UUID    NOT NULL REFERENCES patients(patient_id),
    doctor_id                UUID    NOT NULL REFERENCES doctors(doctor_id),
    requested_date           DATE,
    requested_from           TIME,
    requested_until          TIME,
    priority                 INT     NOT NULL DEFAULT 5 CHECK (priority BETWEEN 1 AND 10),
    reason                   TEXT,
    is_active                BOOLEAN NOT NULL DEFAULT TRUE,
    added_at                 TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    notified_at              TIMESTAMPTZ,
    converted_appointment_id UUID,
    CONSTRAINT chk_time_window CHECK (
        requested_from IS NULL OR requested_until IS NULL OR requested_from < requested_until
    )
);

CREATE INDEX idx_waitlist_active ON waitlist(doctor_id, priority DESC, added_at) WHERE is_active = TRUE;


-- ---------------------------------------------------------------------------
-- Medical Records (versioned)
-- ---------------------------------------------------------------------------
CREATE TABLE medical_records (
    record_id       UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    appointment_id  UUID        NOT NULL,
    patient_id      UUID        NOT NULL REFERENCES patients(patient_id),
    doctor_id       UUID        NOT NULL REFERENCES doctors(doctor_id),
    version         INT         NOT NULL DEFAULT 1,
    is_current      BOOLEAN     NOT NULL DEFAULT TRUE,
    diagnosis_codes TEXT[],
    diagnosis_notes TEXT,
    treatment_plan  TEXT,
    prescriptions   JSONB,
    lab_orders      JSONB,
    follow_up_days  INT,
    vitals          JSONB,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by      UUID        NOT NULL REFERENCES users(user_id)
);

CREATE INDEX idx_records_patient       ON medical_records(patient_id, created_at DESC) WHERE is_current = TRUE;
CREATE INDEX idx_records_diagnosis     ON medical_records USING GIN(diagnosis_codes);
CREATE INDEX idx_records_prescriptions ON medical_records USING GIN(prescriptions);


-- ---------------------------------------------------------------------------
-- Invoices
-- ---------------------------------------------------------------------------
CREATE TABLE invoices (
    invoice_id      UUID           PRIMARY KEY DEFAULT gen_random_uuid(),
    appointment_id  UUID           NOT NULL,
    patient_id      UUID           NOT NULL REFERENCES patients(patient_id),
    subtotal        positive_money NOT NULL,
    discount_amount positive_money NOT NULL DEFAULT 0,
    tax_amount      positive_money NOT NULL DEFAULT 0,
    total_amount    positive_money NOT NULL,
    paid_amount     positive_money NOT NULL DEFAULT 0,
    balance_due     positive_money GENERATED ALWAYS AS (total_amount - paid_amount) STORED,
    due_date        DATE           NOT NULL,
    is_paid         BOOLEAN        NOT NULL DEFAULT FALSE,
    created_at      TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_totals CHECK (total_amount = subtotal - discount_amount + tax_amount)
);

CREATE INDEX idx_invoices_patient ON invoices(patient_id, created_at DESC);
CREATE INDEX idx_invoices_unpaid  ON invoices(due_date) WHERE is_paid = FALSE;


-- ---------------------------------------------------------------------------
-- Invoice Line Items
-- ---------------------------------------------------------------------------
CREATE TABLE invoice_line_items (
    line_id     SERIAL         PRIMARY KEY,
    invoice_id  UUID           NOT NULL REFERENCES invoices(invoice_id),
    description TEXT           NOT NULL,
    cpt_code    TEXT,
    quantity    INT            NOT NULL DEFAULT 1,
    unit_price  positive_money NOT NULL,
    line_total  positive_money GENERATED ALWAYS AS (quantity * unit_price) STORED
);


-- ---------------------------------------------------------------------------
-- Insurance Claims
-- ---------------------------------------------------------------------------
CREATE TABLE insurance_claims (
    claim_id           UUID           PRIMARY KEY DEFAULT gen_random_uuid(),
    invoice_id         UUID           NOT NULL REFERENCES invoices(invoice_id),
    patient_id         UUID           NOT NULL REFERENCES patients(patient_id),
    insurance_provider TEXT           NOT NULL,
    insurance_id       TEXT           NOT NULL,
    claim_amount       positive_money NOT NULL,
    approved_amount    positive_money,
    denial_reason      TEXT,
    status             claim_status   NOT NULL DEFAULT 'draft',
    submitted_at       TIMESTAMPTZ,
    resolved_at        TIMESTAMPTZ,
    metadata           JSONB          NOT NULL DEFAULT '{}',
    created_at         TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    updated_at         TIMESTAMPTZ    NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_claims_status  ON insurance_claims(status, submitted_at);
CREATE INDEX idx_claims_patient ON insurance_claims(patient_id);


-- ---------------------------------------------------------------------------
-- Audit Log (partitioned by year)
-- ---------------------------------------------------------------------------
CREATE TABLE audit_log (
    log_id     BIGSERIAL   NOT NULL,
    table_name TEXT        NOT NULL,
    record_id  TEXT        NOT NULL,
    operation  TEXT        NOT NULL CHECK (operation IN ('INSERT','UPDATE','DELETE')),
    changed_by UUID,
    changed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    old_data   JSONB,
    new_data   JSONB,
    diff       JSONB,
    PRIMARY KEY (log_id, changed_at)
) PARTITION BY RANGE (changed_at);

CREATE TABLE audit_log_2024    PARTITION OF audit_log FOR VALUES FROM ('2024-01-01') TO ('2025-01-01');
CREATE TABLE audit_log_2025    PARTITION OF audit_log FOR VALUES FROM ('2025-01-01') TO ('2026-01-01');
CREATE TABLE audit_log_2026    PARTITION OF audit_log FOR VALUES FROM ('2026-01-01') TO ('2027-01-01');
CREATE TABLE audit_log_default PARTITION OF audit_log DEFAULT;

CREATE INDEX idx_audit_table_record ON audit_log(table_name, record_id, changed_at DESC);
CREATE INDEX idx_audit_changed_by   ON audit_log(changed_by, changed_at DESC);


-- =============================================================================
-- GRANTS — allow Supabase anon and authenticated roles to access all tables
-- =============================================================================

GRANT USAGE ON SCHEMA public TO anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO anon, authenticated;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO anon, authenticated;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO anon, authenticated;
-- =============================================================================
-- MediSchedule: Trigger Functions & Triggers
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. Generic Audit Trigger
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_audit_trigger()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_diff     JSONB := '{}';
    v_old_data JSONB;
    v_new_data JSONB;
    v_key      TEXT;
BEGIN
    IF TG_OP = 'INSERT' THEN
        v_new_data := to_jsonb(NEW);
    ELSIF TG_OP = 'UPDATE' THEN
        v_old_data := to_jsonb(OLD);
        v_new_data := to_jsonb(NEW);
        FOR v_key IN SELECT jsonb_object_keys(v_new_data) LOOP
            IF v_old_data->v_key IS DISTINCT FROM v_new_data->v_key THEN
                v_diff := v_diff || jsonb_build_object(
                    v_key, jsonb_build_object('old', v_old_data->v_key, 'new', v_new_data->v_key)
                );
            END IF;
        END LOOP;
    ELSIF TG_OP = 'DELETE' THEN
        v_old_data := to_jsonb(OLD);
    END IF;

    INSERT INTO audit_log(table_name, record_id, operation, changed_by, old_data, new_data, diff)
    VALUES (
        TG_TABLE_NAME,
        CASE TG_OP
            WHEN 'DELETE' THEN COALESCE(
                v_old_data->>'patient_id', v_old_data->>'appointment_id',
                v_old_data->>'claim_id',   v_old_data->>'record_id',
                v_old_data->>'invoice_id', v_old_data->>'user_id', 'unknown'
            )
            ELSE COALESCE(
                v_new_data->>'patient_id', v_new_data->>'appointment_id',
                v_new_data->>'claim_id',   v_new_data->>'record_id',
                v_new_data->>'invoice_id', v_new_data->>'user_id', 'unknown'
            )
        END,
        TG_OP,
        NULLIF(current_setting('app.current_user_id', TRUE), '')::UUID,
        v_old_data,
        v_new_data,
        CASE WHEN TG_OP = 'UPDATE' THEN v_diff ELSE NULL END
    );

    RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END;
$$;

CREATE TRIGGER trg_audit_patients
    AFTER INSERT OR UPDATE OR DELETE ON patients
    FOR EACH ROW EXECUTE FUNCTION fn_audit_trigger();

CREATE TRIGGER trg_audit_appointments
    AFTER INSERT OR UPDATE OR DELETE ON appointments
    FOR EACH ROW EXECUTE FUNCTION fn_audit_trigger();

CREATE TRIGGER trg_audit_medical_records
    AFTER INSERT OR UPDATE OR DELETE ON medical_records
    FOR EACH ROW EXECUTE FUNCTION fn_audit_trigger();

CREATE TRIGGER trg_audit_insurance_claims
    AFTER INSERT OR UPDATE OR DELETE ON insurance_claims
    FOR EACH ROW EXECUTE FUNCTION fn_audit_trigger();


-- ---------------------------------------------------------------------------
-- 2. Auto-update updated_at
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_updated_at_users
    BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

CREATE TRIGGER trg_updated_at_patients
    BEFORE UPDATE ON patients
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

CREATE TRIGGER trg_updated_at_appointments
    BEFORE UPDATE ON appointments
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();


-- ---------------------------------------------------------------------------
-- 3. Appointment Status State Machine
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_validate_appointment_status_transition()
RETURNS TRIGGER
LANGUAGE plpgsql AS $$
DECLARE
    valid_transitions JSONB := '{
        "scheduled":   ["confirmed","cancelled","rescheduled"],
        "confirmed":   ["checked_in","cancelled","rescheduled","no_show"],
        "checked_in":  ["in_progress","no_show"],
        "in_progress": ["completed"],
        "completed":   [],
        "cancelled":   [],
        "no_show":     ["rescheduled"],
        "rescheduled": ["scheduled"]
    }';
    allowed TEXT[];
BEGIN
    IF OLD.status = NEW.status THEN RETURN NEW; END IF;

    SELECT ARRAY(
        SELECT jsonb_array_elements_text(valid_transitions->OLD.status::TEXT)
    ) INTO allowed;

    IF NOT (NEW.status::TEXT = ANY(allowed)) THEN
        RAISE EXCEPTION 'Invalid appointment status transition: % → %. Allowed: %',
            OLD.status, NEW.status, allowed
            USING ERRCODE = 'P0001';
    END IF;

    IF NEW.status = 'cancelled' AND NEW.cancelled_by IS NULL THEN
        RAISE EXCEPTION 'cancelled_by must be set when cancelling an appointment'
            USING ERRCODE = 'P0002';
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_appt_status_transition
    BEFORE UPDATE OF status ON appointments
    FOR EACH ROW EXECUTE FUNCTION fn_validate_appointment_status_transition();


-- ---------------------------------------------------------------------------
-- 4. Medical Record Versioning
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_version_medical_record()
RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
    UPDATE medical_records
    SET is_current = FALSE
    WHERE patient_id     = OLD.patient_id
      AND appointment_id = OLD.appointment_id
      AND is_current     = TRUE
      AND record_id     <> NEW.record_id;

    NEW.version    := OLD.version + 1;
    NEW.is_current := TRUE;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_version_medical_record
    BEFORE UPDATE ON medical_records
    FOR EACH ROW EXECUTE FUNCTION fn_version_medical_record();


-- ---------------------------------------------------------------------------
-- 5. Patient Full-Text Search Vector
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_update_patient_search_vector()
RETURNS TRIGGER
LANGUAGE plpgsql AS $$
DECLARE
    v_full_name TEXT;
BEGIN
    SELECT full_name INTO v_full_name
    FROM users WHERE user_id = NEW.patient_id;

    NEW.search_vector :=
        setweight(to_tsvector('english', COALESCE(v_full_name, '')),                         'A') ||
        setweight(to_tsvector('english', COALESCE(NEW.insurance_provider, '')),              'B') ||
        setweight(to_tsvector('english', COALESCE(array_to_string(NEW.allergies, ' '), '')), 'C');

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_patient_search_vector
    BEFORE INSERT OR UPDATE ON patients
    FOR EACH ROW EXECUTE FUNCTION fn_update_patient_search_vector();


-- ---------------------------------------------------------------------------
-- 6. Auto-mark Invoice as Paid
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_check_invoice_paid()
RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.paid_amount >= NEW.total_amount THEN
        NEW.is_paid := TRUE;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_invoice_paid_check
    BEFORE UPDATE OF paid_amount ON invoices
    FOR EACH ROW EXECUTE FUNCTION fn_check_invoice_paid();


-- ---------------------------------------------------------------------------
-- 7. Waitlist Notification on Cancellation
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_notify_waitlist_on_cancellation()
RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.status IN ('cancelled', 'no_show')
    AND OLD.status NOT IN ('cancelled', 'no_show') THEN

        UPDATE waitlist
        SET notified_at = NOW()
        WHERE waitlist_id = (
            SELECT waitlist_id FROM waitlist
            WHERE doctor_id   = NEW.doctor_id
              AND is_active   = TRUE
              AND notified_at IS NULL
              AND (requested_date IS NULL OR requested_date = NEW.scheduled_start::DATE)
            ORDER BY priority DESC, added_at ASC
            LIMIT 1
        );

        PERFORM pg_notify(
            'waitlist_slot_available',
            json_build_object(
                'doctor_id',  NEW.doctor_id,
                'slot_start', NEW.scheduled_start,
                'slot_end',   NEW.scheduled_end
            )::TEXT
        );
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_waitlist_notify
    AFTER UPDATE OF status ON appointments
    FOR EACH ROW EXECUTE FUNCTION fn_notify_waitlist_on_cancellation();
-- =============================================================================
-- MediSchedule: Stored Procedures
-- =============================================================================


-- ---------------------------------------------------------------------------
-- PROCEDURE: book_appointment
-- ---------------------------------------------------------------------------
-- ---------------------------------------------------------------------------
-- FUNCTION: book_appointment (returns the new appointment_id)
-- Converted from PROCEDURE to FUNCTION for Supabase RPC compatibility
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION book_appointment(
    p_patient_id       UUID,
    p_doctor_id        UUID,
    p_room_id          INT,
    p_start            TIMESTAMPTZ,
    p_end              TIMESTAMPTZ,
    p_appointment_type TEXT,
    p_chief_complaint  TEXT,
    p_created_by       UUID
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_dow       day_of_week;
    v_schedule  RECORD;
    v_exception RECORD;
    v_lock_key  BIGINT;
    v_appt_id   UUID;
BEGIN
    v_dow := TRIM(LOWER(TO_CHAR(p_start AT TIME ZONE 'UTC', 'Day')))::day_of_week;

    SELECT * INTO v_schedule
    FROM doctor_schedules
    WHERE doctor_id   = p_doctor_id
      AND day_of_week = v_dow
      AND is_active   = TRUE
      AND valid_from <= p_start::DATE
      AND (valid_until IS NULL OR valid_until >= p_start::DATE)
      AND start_time  <= p_start::TIME
      AND end_time    >= p_end::TIME;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Doctor % has no availability on % between % and %',
            p_doctor_id, v_dow, p_start::TIME, p_end::TIME
            USING ERRCODE = 'P0010';
    END IF;

    SELECT * INTO v_exception
    FROM schedule_exceptions
    WHERE doctor_id      = p_doctor_id
      AND exception_date = p_start::DATE
      AND (
          is_full_day = TRUE
          OR (blocked_from <= p_start::TIME AND blocked_until >= p_end::TIME)
      );

    IF FOUND THEN
        RAISE EXCEPTION 'Doctor % is unavailable on % due to: %',
            p_doctor_id, p_start::DATE, COALESCE(v_exception.reason, 'scheduled exception')
            USING ERRCODE = 'P0011';
    END IF;

    v_lock_key := ('x' || md5(p_doctor_id::TEXT || p_start::DATE::TEXT))::BIT(63)::BIGINT;

    IF NOT pg_try_advisory_xact_lock(v_lock_key) THEN
        RAISE EXCEPTION 'Unable to acquire booking lock for doctor % on %. Please retry.',
            p_doctor_id, p_start::DATE
            USING ERRCODE = 'P0012';
    END IF;

    BEGIN
        INSERT INTO appointment_locks(doctor_id, time_range, appointment_id)
        VALUES (p_doctor_id, tstzrange(p_start, p_end, '[)'), gen_random_uuid());
    EXCEPTION WHEN exclusion_violation THEN
        RAISE EXCEPTION 'Doctor % already has an appointment overlapping % to %',
            p_doctor_id, p_start, p_end
            USING ERRCODE = 'P0013';
    END;

    IF p_room_id IS NOT NULL THEN
        BEGIN
            INSERT INTO room_locks(room_id, time_range, appointment_id)
            VALUES (p_room_id, tstzrange(p_start, p_end, '[)'), gen_random_uuid());
        EXCEPTION WHEN exclusion_violation THEN
            RAISE EXCEPTION 'Room % is already booked from % to %',
                p_room_id, p_start, p_end
                USING ERRCODE = 'P0014';
        END;
    END IF;

    v_appt_id := gen_random_uuid();

    INSERT INTO appointments(
        appointment_id, patient_id, doctor_id, room_id,
        scheduled_start, scheduled_end, status,
        appointment_type, chief_complaint, created_by
    )
    VALUES (
        v_appt_id, p_patient_id, p_doctor_id, p_room_id,
        p_start, p_end, 'scheduled',
        p_appointment_type, p_chief_complaint, p_created_by
    );

    UPDATE appointment_locks
    SET appointment_id = v_appt_id
    WHERE doctor_id  = p_doctor_id
      AND time_range = tstzrange(p_start, p_end, '[)');

    IF p_room_id IS NOT NULL THEN
        UPDATE room_locks
        SET appointment_id = v_appt_id
        WHERE room_id    = p_room_id
          AND time_range = tstzrange(p_start, p_end, '[)');
    END IF;

    RETURN v_appt_id;
END;
$$;


-- ---------------------------------------------------------------------------
-- FUNCTION: complete_appointment (returns the new invoice_id)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION complete_appointment(
    p_appointment_id  UUID,
    p_actual_start    TIMESTAMPTZ,
    p_actual_end      TIMESTAMPTZ,
    p_diagnosis_codes TEXT[],
    p_diagnosis_notes TEXT,
    p_treatment_plan  TEXT,
    p_prescriptions   JSONB,
    p_vitals          JSONB,
    p_cpt_codes       JSONB,
    p_follow_up_days  INT,
    p_completed_by    UUID
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_appt       RECORD;
    v_doctor     RECORD;
    v_subtotal   NUMERIC(12,2) := 0;
    v_total      NUMERIC(12,2);
    v_invoice_id UUID;
    v_record_id  UUID;
    v_cpt_item   JSONB;
    v_line_total NUMERIC(12,2);
BEGIN
    SELECT a.*, p.insurance_provider, p.insurance_id
    INTO v_appt
    FROM appointments a
    JOIN patients p ON p.patient_id = a.patient_id
    WHERE a.appointment_id = p_appointment_id
      AND a.status NOT IN ('completed', 'cancelled');

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Appointment % not found or already finalized', p_appointment_id
            USING ERRCODE = 'P0020';
    END IF;

    SELECT * INTO v_doctor FROM doctors WHERE doctor_id = v_appt.doctor_id;

    UPDATE appointments
    SET status       = 'completed',
        actual_start = p_actual_start,
        actual_end   = p_actual_end
    WHERE appointment_id  = p_appointment_id
      AND scheduled_start = v_appt.scheduled_start;

    v_record_id := gen_random_uuid();
    INSERT INTO medical_records(
        record_id, appointment_id, patient_id, doctor_id,
        diagnosis_codes, diagnosis_notes, treatment_plan,
        prescriptions, vitals, follow_up_days, created_by
    )
    VALUES (
        v_record_id, p_appointment_id, v_appt.patient_id, v_appt.doctor_id,
        p_diagnosis_codes, p_diagnosis_notes, p_treatment_plan,
        p_prescriptions, p_vitals, p_follow_up_days, p_completed_by
    );

    v_subtotal := v_doctor.consultation_fee;

    FOR v_cpt_item IN SELECT * FROM jsonb_array_elements(p_cpt_codes) LOOP
        v_line_total := (v_cpt_item->>'quantity')::INT * (v_cpt_item->>'unit_price')::NUMERIC;
        v_subtotal   := v_subtotal + v_line_total;
    END LOOP;

    v_total      := v_subtotal;
    v_invoice_id := gen_random_uuid();

    INSERT INTO invoices(
        invoice_id, appointment_id, patient_id,
        subtotal, discount_amount, tax_amount, total_amount, due_date
    )
    VALUES (
        v_invoice_id, p_appointment_id, v_appt.patient_id,
        v_subtotal, 0, 0, v_total,
        CURRENT_DATE + INTERVAL '30 days'
    );

    INSERT INTO invoice_line_items(invoice_id, description, quantity, unit_price)
    VALUES (v_invoice_id, 'Consultation fee - ' || v_doctor.specialty, 1, v_doctor.consultation_fee);

    FOR v_cpt_item IN SELECT * FROM jsonb_array_elements(p_cpt_codes) LOOP
        INSERT INTO invoice_line_items(invoice_id, description, cpt_code, quantity, unit_price)
        VALUES (
            v_invoice_id,
            v_cpt_item->>'description',
            v_cpt_item->>'code',
            (v_cpt_item->>'quantity')::INT,
            (v_cpt_item->>'unit_price')::NUMERIC
        );
    END LOOP;

    IF v_appt.insurance_provider IS NOT NULL THEN
        INSERT INTO insurance_claims(
            invoice_id, patient_id, insurance_provider, insurance_id,
            claim_amount, status, submitted_at
        )
        VALUES (
            v_invoice_id, v_appt.patient_id, v_appt.insurance_provider,
            v_appt.insurance_id, v_total, 'submitted', NOW()
        );
    END IF;

    RETURN v_invoice_id;
END;
$$;


-- ---------------------------------------------------------------------------
-- FUNCTION: reschedule_appointment (returns new appointment_id)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION reschedule_appointment(
    p_appointment_id UUID,
    p_old_start      TIMESTAMPTZ,
    p_new_start      TIMESTAMPTZ,
    p_new_end        TIMESTAMPTZ,
    p_rescheduled_by UUID
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_appt               RECORD;
    v_new_appointment_id UUID;
BEGIN
    SELECT * INTO v_appt
    FROM appointments
    WHERE appointment_id  = p_appointment_id
      AND scheduled_start = p_old_start
      AND status NOT IN ('completed', 'cancelled');

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Cannot reschedule appointment %: not found or already finalized',
            p_appointment_id USING ERRCODE = 'P0030';
    END IF;

    UPDATE appointments
    SET status              = 'rescheduled',
        cancelled_by        = p_rescheduled_by,
        cancellation_reason = 'Rescheduled by user'
    WHERE appointment_id  = p_appointment_id
      AND scheduled_start = p_old_start;

    DELETE FROM appointment_locks WHERE appointment_id = p_appointment_id;
    DELETE FROM room_locks         WHERE appointment_id = p_appointment_id;

    v_new_appointment_id := book_appointment(
        v_appt.patient_id, v_appt.doctor_id, v_appt.room_id,
        p_new_start, p_new_end,
        v_appt.appointment_type, v_appt.chief_complaint,
        p_rescheduled_by
    );

    UPDATE appointments
    SET metadata = metadata || jsonb_build_object(
        'rescheduled_from', p_appointment_id,
        'original_slot',    p_old_start
    )
    WHERE appointment_id  = v_new_appointment_id
      AND scheduled_start = p_new_start;

    RETURN v_new_appointment_id;
END;
$$;
-- =============================================================================
-- MediSchedule: Functions
-- =============================================================================


-- ---------------------------------------------------------------------------
-- get_available_slots
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION get_available_slots(
    p_doctor_id UUID,
    p_date      DATE
)
RETURNS TABLE (
    slot_start   TIMESTAMPTZ,
    slot_end     TIMESTAMPTZ,
    is_available BOOLEAN
)
LANGUAGE plpgsql STABLE AS $$
DECLARE
    v_dow      day_of_week;
    v_schedule RECORD;
BEGIN
    v_dow := LOWER(TRIM(TO_CHAR(p_date, 'Day')))::day_of_week;

    SELECT * INTO v_schedule
    FROM doctor_schedules
    WHERE doctor_id   = p_doctor_id
      AND day_of_week = v_dow
      AND is_active   = TRUE
      AND valid_from <= p_date
      AND (valid_until IS NULL OR valid_until >= p_date);

    IF NOT FOUND THEN
        RETURN;
    END IF;

    RETURN QUERY
    WITH all_slots AS (
        SELECT
            g.slot_start::TIMESTAMPTZ AS slot_start,
            (g.slot_start + (v_schedule.slot_duration || ' minutes')::INTERVAL)::TIMESTAMPTZ AS slot_end
        FROM generate_series(
            (p_date + v_schedule.start_time)::TIMESTAMPTZ,
            (p_date + v_schedule.end_time - (v_schedule.slot_duration || ' minutes')::INTERVAL)::TIMESTAMPTZ,
            (v_schedule.slot_duration || ' minutes')::INTERVAL
        ) AS g(slot_start)
    ),
    blocked_by_exception AS (
        SELECT TRUE AS blocked
        FROM schedule_exceptions
        WHERE doctor_id      = p_doctor_id
          AND exception_date = p_date
          AND is_full_day    = TRUE
        LIMIT 1
    )
    SELECT
        s.slot_start,
        s.slot_end,
        NOT EXISTS (
            SELECT 1 FROM blocked_by_exception
            UNION ALL
            SELECT 1 FROM appointment_locks al
            WHERE al.doctor_id  = p_doctor_id
              AND al.time_range && tstzrange(s.slot_start, s.slot_end, '[)')
        ) AS is_available
    FROM all_slots s
    ORDER BY s.slot_start;
END;
$$;


-- ---------------------------------------------------------------------------
-- search_patients
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION search_patients(
    p_query  TEXT,
    p_limit  INT DEFAULT 20,
    p_offset INT DEFAULT 0
)
RETURNS TABLE (
    patient_id UUID,
    full_name  TEXT,
    email      TEXT,
    dob        DATE,
    rank       REAL
)
LANGUAGE sql STABLE AS $$
    SELECT
        p.patient_id,
        u.full_name,
        u.email,
        p.date_of_birth,
        ts_rank(p.search_vector, websearch_to_tsquery('english', p_query)) AS rank
    FROM patients p
    JOIN users u ON u.user_id = p.patient_id
    WHERE
        p.search_vector @@ websearch_to_tsquery('english', p_query)
        OR u.full_name % p_query
        OR u.email ILIKE '%' || p_query || '%'
    ORDER BY rank DESC, u.full_name
    LIMIT p_limit
    OFFSET p_offset;
$$;


-- ---------------------------------------------------------------------------
-- get_department_tree
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION get_department_tree(p_root_dept_id INT DEFAULT NULL)
RETURNS TABLE (
    dept_id   INT,
    name      TEXT,
    parent_id INT,
    depth     INT,
    path      TEXT,
    head_name TEXT
)
LANGUAGE sql STABLE AS $$
    WITH RECURSIVE dept_tree AS (
        SELECT
            d.dept_id,
            d.name,
            d.parent_dept_id AS parent_id,
            0                AS depth,
            d.name           AS path
        FROM departments d
        WHERE (p_root_dept_id IS NULL AND d.parent_dept_id IS NULL)
           OR (p_root_dept_id IS NOT NULL AND d.dept_id = p_root_dept_id)

        UNION ALL

        SELECT
            child.dept_id,
            child.name,
            child.parent_dept_id,
            parent.depth + 1,
            parent.path || ' > ' || child.name
        FROM departments child
        JOIN dept_tree parent ON parent.dept_id = child.parent_dept_id
    )
    SELECT
        dt.dept_id,
        dt.name,
        dt.parent_id,
        dt.depth,
        dt.path,
        u.full_name AS head_name
    FROM dept_tree dt
    LEFT JOIN departments d ON d.dept_id = dt.dept_id
    LEFT JOIN users u       ON u.user_id = d.head_user_id
    ORDER BY dt.path;
$$;


-- ---------------------------------------------------------------------------
-- find_schedule_gaps
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION find_schedule_gaps(
    p_doctor_id  UUID,
    p_week_start DATE
)
RETURNS TABLE (
    gap_date    DATE,
    gap_start   TIME,
    gap_end     TIME,
    gap_minutes INT
)
LANGUAGE sql STABLE AS $$
    WITH week_days AS (
        SELECT (p_week_start + (n || ' days')::INTERVAL)::DATE AS day
        FROM generate_series(0, 6) n
    ),
    all_slots AS (
        SELECT wd.day, s.slot_start, s.slot_end, s.is_available
        FROM week_days wd
        CROSS JOIN LATERAL get_available_slots(p_doctor_id, wd.day) s
    ),
    numbered AS (
        SELECT
            day, slot_start, slot_end, is_available,
            ROW_NUMBER() OVER (PARTITION BY day ORDER BY slot_start)               AS rn,
            ROW_NUMBER() OVER (PARTITION BY day, is_available ORDER BY slot_start) AS grp_rn
        FROM all_slots
    ),
    islands AS (
        SELECT
            day,
            MIN(slot_start)::TIME AS gap_start,
            MAX(slot_end)::TIME   AS gap_end,
            is_available,
            (rn - grp_rn)         AS island_id
        FROM numbered
        GROUP BY day, is_available, (rn - grp_rn)
    )
    SELECT
        day                                                  AS gap_date,
        gap_start,
        gap_end,
        EXTRACT(EPOCH FROM (gap_end - gap_start))::INT / 60 AS gap_minutes
    FROM islands
    WHERE is_available = TRUE
      AND EXTRACT(EPOCH FROM (gap_end - gap_start)) >= 1800
    ORDER BY gap_date, gap_start;
$$;


-- Grant execute on all functions to anon and authenticated roles
GRANT EXECUTE ON FUNCTION get_available_slots(UUID, DATE)     TO anon, authenticated;
GRANT EXECUTE ON FUNCTION search_patients(TEXT, INT, INT)     TO anon, authenticated;
GRANT EXECUTE ON FUNCTION get_department_tree(INT)            TO anon, authenticated;
GRANT EXECUTE ON FUNCTION find_schedule_gaps(UUID, DATE)      TO anon, authenticated;
GRANT EXECUTE ON FUNCTION book_appointment(UUID,UUID,INT,TIMESTAMPTZ,TIMESTAMPTZ,TEXT,TEXT,UUID) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION complete_appointment(UUID,TIMESTAMPTZ,TIMESTAMPTZ,TEXT[],TEXT,TEXT,JSONB,JSONB,JSONB,INT,UUID) TO anon, authenticated;
-- =============================================================================
-- MediSchedule: Views & Materialized Views
-- =============================================================================


-- ---------------------------------------------------------------------------
-- MATERIALIZED VIEW: doctor_utilization_monthly
-- ---------------------------------------------------------------------------
CREATE MATERIALIZED VIEW doctor_utilization_monthly AS
WITH monthly_stats AS (
    SELECT
        d.doctor_id,
        u.full_name                                             AS doctor_name,
        d.specialty,
        dept.name                                               AS department,
        DATE_TRUNC('month', a.scheduled_start)                 AS month,
        COUNT(*)                                                AS total_appointments,
        COUNT(*) FILTER (WHERE a.status = 'completed')         AS completed,
        COUNT(*) FILTER (WHERE a.status = 'no_show')           AS no_shows,
        COUNT(*) FILTER (WHERE a.status = 'cancelled')         AS cancelled,
        AVG(
            EXTRACT(EPOCH FROM (a.actual_end - a.actual_start)) / 60.0
        ) FILTER (WHERE a.actual_start IS NOT NULL)            AS avg_duration_minutes,
        SUM(inv.total_amount) FILTER (WHERE inv.invoice_id IS NOT NULL) AS revenue_generated
    FROM doctors d
    JOIN users u          ON u.user_id    = d.doctor_id
    JOIN departments dept ON dept.dept_id = d.dept_id
    JOIN appointments a   ON a.doctor_id  = d.doctor_id
    LEFT JOIN invoices inv ON inv.appointment_id = a.appointment_id
    WHERE a.scheduled_start >= NOW() - INTERVAL '2 years'
    GROUP BY d.doctor_id, u.full_name, d.specialty, dept.name,
             DATE_TRUNC('month', a.scheduled_start)
),
ranked AS (
    SELECT
        *,
        ROUND(100.0 * completed / NULLIF(total_appointments, 0), 2) AS completion_rate_pct,
        ROUND(100.0 * no_shows  / NULLIF(total_appointments, 0), 2) AS no_show_rate_pct,
        RANK() OVER (
            PARTITION BY specialty, month
            ORDER BY revenue_generated DESC NULLS LAST
        ) AS revenue_rank_in_specialty,
        SUM(total_appointments) OVER (
            PARTITION BY doctor_id
            ORDER BY month
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS cumulative_appointments,
        completed - LAG(completed, 1, 0) OVER (
            PARTITION BY doctor_id ORDER BY month
        ) AS mom_completed_change
    FROM monthly_stats
)
SELECT * FROM ranked
WITH DATA;

CREATE UNIQUE INDEX idx_util_monthly_pk       ON doctor_utilization_monthly(doctor_id, month);
CREATE INDEX        idx_util_monthly_specialty ON doctor_utilization_monthly(specialty, month);


-- ---------------------------------------------------------------------------
-- VIEW: patient_appointment_history
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW patient_appointment_history AS
SELECT
    a.appointment_id,
    a.patient_id,
    u_pat.full_name                                     AS patient_name,
    a.doctor_id,
    u_doc.full_name                                     AS doctor_name,
    d.specialty,
    a.scheduled_start,
    a.status,
    a.appointment_type,
    ROW_NUMBER() OVER (
        PARTITION BY a.patient_id
        ORDER BY a.scheduled_start
    ) AS visit_number,
    a.scheduled_start::DATE - LAG(a.scheduled_start::DATE) OVER (
        PARTITION BY a.patient_id
        ORDER BY a.scheduled_start
    ) AS days_since_last_visit,
    COUNT(*) FILTER (WHERE a.status = 'no_show') OVER (
        PARTITION BY a.patient_id
        ORDER BY a.scheduled_start
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS cumulative_no_shows,
    i.total_amount AS invoice_total,
    SUM(COALESCE(i.total_amount, 0)) OVER (
        PARTITION BY a.patient_id
        ORDER BY a.scheduled_start
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS cumulative_spend
FROM appointments a
JOIN users u_pat ON u_pat.user_id = a.patient_id
JOIN users u_doc ON u_doc.user_id = a.doctor_id
JOIN doctors d   ON d.doctor_id   = a.doctor_id
LEFT JOIN invoices i ON i.appointment_id = a.appointment_id;


-- ---------------------------------------------------------------------------
-- VIEW: revenue_dashboard
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW revenue_dashboard AS
WITH daily AS (
    SELECT
        i.created_at::DATE                                      AS invoice_date,
        d.specialty,
        SUM(i.total_amount)                                     AS daily_revenue,
        SUM(i.paid_amount)                                      AS daily_collected,
        COUNT(DISTINCT i.invoice_id)                            AS invoice_count,
        COUNT(DISTINCT ic.claim_id) FILTER (WHERE ic.status = 'approved') AS claims_approved,
        SUM(ic.approved_amount)                                 AS insurance_collected
    FROM invoices i
    JOIN appointments a    ON a.appointment_id = i.appointment_id
    JOIN doctors d         ON d.doctor_id      = a.doctor_id
    LEFT JOIN insurance_claims ic ON ic.invoice_id = i.invoice_id
    GROUP BY i.created_at::DATE, d.specialty
)
SELECT
    invoice_date,
    specialty,
    daily_revenue,
    daily_collected,
    invoice_count,
    claims_approved,
    insurance_collected,
    ROUND(AVG(daily_revenue) OVER (
        PARTITION BY specialty
        ORDER BY invoice_date
        ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
    ), 2) AS rolling_7d_avg_revenue,
    SUM(daily_revenue) OVER (
        PARTITION BY specialty, DATE_TRUNC('month', invoice_date)
        ORDER BY invoice_date
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS mtd_revenue,
    ROUND(100.0 * daily_collected / NULLIF(daily_revenue, 0), 2) AS collection_rate_pct
FROM daily
ORDER BY invoice_date DESC, specialty;


-- Grant select on views
GRANT SELECT ON patient_appointment_history  TO anon, authenticated;
GRANT SELECT ON revenue_dashboard            TO anon, authenticated;
GRANT SELECT ON doctor_utilization_monthly   TO anon, authenticated;
-- =============================================================================
-- MediSchedule: Seed Data
-- =============================================================================

-- Departments
INSERT INTO departments (dept_id, name, parent_dept_id) VALUES
    (1, 'Medical Services', NULL),
    (2, 'Cardiology',       1),
    (3, 'Neurology',        1),
    (4, 'Pediatrics',       1),
    (5, 'Orthopedics',      1),
    (6, 'Administration',   NULL),
    (7, 'Billing',          6);

-- Users
INSERT INTO users (user_id, email, full_name, role, password_hash) VALUES
    ('00000000-0000-0000-0000-000000000001', 'admin@clinic.com',     'System Admin',      'admin',        'hashed'),
    ('00000000-0000-0000-0001-000000000001', 'dr.smith@clinic.com',  'Dr. Sarah Smith',   'doctor',       'hashed'),
    ('00000000-0000-0000-0001-000000000002', 'dr.patel@clinic.com',  'Dr. Raj Patel',     'doctor',       'hashed'),
    ('00000000-0000-0000-0001-000000000003', 'dr.chen@clinic.com',   'Dr. Wei Chen',      'doctor',       'hashed'),
    ('00000000-0000-0000-0002-000000000001', 'alice@email.com',      'Alice Johnson',     'patient',      'hashed'),
    ('00000000-0000-0000-0002-000000000002', 'bob@email.com',        'Bob Williams',      'patient',      'hashed'),
    ('00000000-0000-0000-0002-000000000003', 'carol@email.com',      'Carol Davis',       'patient',      'hashed'),
    ('00000000-0000-0000-0003-000000000001', 'reception@clinic.com', 'Jane Receptionist', 'receptionist', 'hashed'),
    ('00000000-0000-0000-0004-000000000001', 'billing@clinic.com',   'Mark Billing',      'billing_staff','hashed');

-- Doctors
INSERT INTO doctors (doctor_id, dept_id, specialty, license_number, consultation_fee, metadata) VALUES
    ('00000000-0000-0000-0001-000000000001', 2, 'Cardiology', 'LIC-CARD-001', 250.00,
        '{"languages": ["English","Spanish"], "accepting_new_patients": true,  "years_experience": 15}'),
    ('00000000-0000-0000-0001-000000000002', 3, 'Neurology',  'LIC-NEUR-001', 300.00,
        '{"languages": ["English","Hindi"],   "accepting_new_patients": true,  "years_experience": 12}'),
    ('00000000-0000-0000-0001-000000000003', 4, 'Pediatrics', 'LIC-PEDI-001', 200.00,
        '{"languages": ["English","Mandarin"],"accepting_new_patients": false, "years_experience": 8}');

-- Patients
INSERT INTO patients (patient_id, date_of_birth, gender, phone, blood_type, allergies, insurance_provider, insurance_id) VALUES
    ('00000000-0000-0000-0002-000000000001', '1985-03-15', 'F', '+1-555-0101', 'A+', ARRAY['Penicillin','Sulfa'], 'BlueCross', 'BC-10001'),
    ('00000000-0000-0000-0002-000000000002', '1972-07-22', 'M', '+1-555-0102', 'O-', ARRAY['Latex'],             'Aetna',     'AET-20002'),
    ('00000000-0000-0000-0002-000000000003', '1995-11-30', 'F', '+1-555-0103', 'B+', ARRAY[]::TEXT[],            NULL,        NULL);

-- Doctor Schedules (valid_from set to past date so bookings always work)
INSERT INTO doctor_schedules (doctor_id, day_of_week, start_time, end_time, slot_duration, valid_from) VALUES
    ('00000000-0000-0000-0001-000000000001', 'monday',    '08:00', '17:00', 30, '2020-01-01'),
    ('00000000-0000-0000-0001-000000000001', 'tuesday',   '08:00', '17:00', 30, '2020-01-01'),
    ('00000000-0000-0000-0001-000000000001', 'wednesday', '08:00', '13:00', 30, '2020-01-01'),
    ('00000000-0000-0000-0001-000000000001', 'thursday',  '08:00', '17:00', 30, '2020-01-01'),
    ('00000000-0000-0000-0001-000000000001', 'friday',    '08:00', '15:00', 30, '2020-01-01'),
    ('00000000-0000-0000-0001-000000000002', 'monday',    '09:00', '18:00', 45, '2020-01-01'),
    ('00000000-0000-0000-0001-000000000002', 'wednesday', '09:00', '18:00', 45, '2020-01-01'),
    ('00000000-0000-0000-0001-000000000002', 'friday',    '09:00', '14:00', 45, '2020-01-01'),
    ('00000000-0000-0000-0001-000000000003', 'tuesday',   '07:00', '15:00', 20, '2020-01-01'),
    ('00000000-0000-0000-0001-000000000003', 'thursday',  '07:00', '15:00', 20, '2020-01-01'),
    ('00000000-0000-0000-0001-000000000003', 'saturday',  '08:00', '12:00', 20, '2020-01-01');

-- Rooms
INSERT INTO rooms (room_number, room_type, dept_id, equipment) VALUES
    ('C-101', 'consultation', 2, '["ECG", "Blood Pressure Monitor"]'),
    ('C-102', 'consultation', 3, '["Neurological Reflex Kit", "Ophthalmoscope"]'),
    ('C-103', 'consultation', 4, '["Pediatric Scale", "Otoscope"]'),
    ('P-201', 'procedure',    2, '["Stress Test Equipment", "Defibrillator"]'),
    ('L-301', 'lab',          1, '["Centrifuge", "Microscope"]');

-- Populate search vectors
UPDATE patients SET updated_at = NOW();