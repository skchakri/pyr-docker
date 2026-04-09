-- mask_pii.sql — Mask all PII fields after import into dev database
-- Run via: mysql -u root -p <db_name> < mask_pii.sql

-- ============================================================
-- tree_users
-- ============================================================
UPDATE tree_users SET
  email          = CONCAT('dev+', id, '@example.com'),
  first_name     = CONCAT(LEFT(first_name, 1), '***'),
  last_name      = CONCAT(LEFT(last_name, 1), '***'),
  phone          = CONCAT('555-000-', LPAD(id % 10000, 4, '0')),
  mobile_phone   = CONCAT('555-000-', LPAD(id % 10000, 4, '0')),
  fax            = NULL,
  birth_date     = CASE
                     WHEN birth_date IS NOT NULL
                     THEN DATE(CONCAT(YEAR(birth_date), '-', LPAD(FLOOR(1 + RAND() * 12), 2, '0'), '-', LPAD(FLOOR(1 + RAND() * 28), 2, '0')))
                     ELSE NULL
                   END,
  address1       = '123 Dev St',
  address2       = NULL,
  address3       = NULL,
  city           = 'Test City',
  state          = 'TS',
  zip            = '00000',
  mail_address1  = CASE WHEN mail_address1 IS NOT NULL THEN '123 Dev St' ELSE NULL END,
  mail_address2  = NULL,
  mail_address3  = NULL,
  mail_city      = CASE WHEN mail_city IS NOT NULL THEN 'Test City' ELSE NULL END,
  mail_state     = CASE WHEN mail_state IS NOT NULL THEN 'TS' ELSE NULL END,
  mail_zip       = CASE WHEN mail_zip IS NOT NULL THEN '00000' ELSE NULL END,
  other_address1 = CASE WHEN other_address1 IS NOT NULL THEN '123 Dev St' ELSE NULL END,
  other_address2 = NULL,
  other_address3 = NULL,
  other_city     = CASE WHEN other_city IS NOT NULL THEN 'Test City' ELSE NULL END,
  other_state    = CASE WHEN other_state IS NOT NULL THEN 'TS' ELSE NULL END,
  other_zip      = CASE WHEN other_zip IS NOT NULL THEN '00000' ELSE NULL END;

-- ============================================================
-- users (Devise)
-- ============================================================
-- bcrypt hash of "password" (cost 10)
UPDATE users SET
  email                  = CONCAT('dev+', id, '@example.com'),
  encrypted_password     = '$2a$10$8KzPMGnJPsSMwQO0BnUYxOJGhsVbLRGNMq3PdSBNPMBZgCRz9MaKS',
  reset_password_token   = NULL,
  confirmation_token     = NULL,
  unlock_token           = NULL,
  current_sign_in_ip     = '127.0.0.1',
  last_sign_in_ip        = '127.0.0.1';

-- ============================================================
-- pyr_profiles
-- ============================================================
UPDATE pyr_profiles SET
  first_name = CONCAT(LEFT(first_name, 1), '***'),
  last_name  = CONCAT(LEFT(last_name, 1), '***'),
  email      = CONCAT('dev+profile+', id, '@example.com'),
  phone      = CONCAT('555-000-', LPAD(id % 10000, 4, '0'));

-- ============================================================
-- pyr_addresses
-- ============================================================
UPDATE pyr_addresses SET
  firstname  = CONCAT(LEFT(firstname, 1), '***'),
  lastname   = CONCAT(LEFT(lastname, 1), '***'),
  address1   = '123 Dev St',
  address2   = NULL,
  city       = 'Test City',
  state_name = 'Test State',
  zipcode    = '00000',
  phone      = CONCAT('555-000-', LPAD(id % 10000, 4, '0'));

-- ============================================================
-- pyr_contacts
-- ============================================================
UPDATE pyr_contacts SET
  first_name = CONCAT(LEFT(first_name, 1), '***'),
  last_name  = CONCAT(LEFT(last_name, 1), '***'),
  address1   = CASE WHEN address1 IS NOT NULL THEN '123 Dev St' ELSE NULL END,
  address2   = NULL,
  city       = CASE WHEN city IS NOT NULL THEN 'Test City' ELSE NULL END,
  state      = CASE WHEN state IS NOT NULL THEN 'TS' ELSE NULL END,
  zip        = CASE WHEN zip IS NOT NULL THEN '00000' ELSE NULL END;

-- ============================================================
-- pyr_contact_emails
-- ============================================================
UPDATE pyr_contact_emails SET
  email = CONCAT('contact+', id, '@example.com');

-- ============================================================
-- pyr_contact_phone_numbers
-- ============================================================
UPDATE pyr_contact_phone_numbers SET
  phone_number = CONCAT('555-999-', LPAD(id % 10000, 4, '0'));
