-- ============================================================
-- Smart Society Complaint Management System
-- MySQL Schema — DBA Academic Project
-- ============================================================

CREATE DATABASE IF NOT EXISTS society_db CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE society_db;

-- ============================================================
-- TABLE 1: users
-- ============================================================
CREATE TABLE IF NOT EXISTS users (
  user_id       INT AUTO_INCREMENT PRIMARY KEY,
  full_name     VARCHAR(100) NOT NULL,
  email         VARCHAR(100) UNIQUE NOT NULL,
  password VARCHAR(255) NOT NULL,
  role          ENUM('member','staff','admin') NOT NULL,
  room_number   VARCHAR(10),
  phone         VARCHAR(15),
  is_active     BOOLEAN DEFAULT TRUE,
  created_at    TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================
-- TABLE 2: complaints
-- ============================================================
CREATE TABLE IF NOT EXISTS complaints (
  complaint_id INT AUTO_INCREMENT PRIMARY KEY,
  member_id   INT NOT NULL,
  category     ENUM('electrical','plumbing','cleanliness','food','security','noise','other') NOT NULL,
  title        VARCHAR(200) NOT NULL,
  description  TEXT NOT NULL,
  priority     ENUM('low','medium','high') DEFAULT 'medium',
  status       ENUM('pending','in_progress','resolved','rejected') DEFAULT 'pending',
  assigned_to  INT,
  created_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  FOREIGN KEY (member_id) REFERENCES users(user_id) ON DELETE CASCADE,
  FOREIGN KEY (assigned_to) REFERENCES users(user_id) ON DELETE SET NULL
);

-- ============================================================
-- TABLE 3: complaint_logs (Audit Trail)
-- ============================================================
CREATE TABLE IF NOT EXISTS complaint_logs (
  log_id       INT AUTO_INCREMENT PRIMARY KEY,
  complaint_id INT NOT NULL,
  changed_by   INT NOT NULL,
  old_status   VARCHAR(20),
  new_status   VARCHAR(20),
  remark       TEXT,
  changed_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (complaint_id) REFERENCES complaints(complaint_id) ON DELETE CASCADE,
  FOREIGN KEY (changed_by) REFERENCES users(user_id)
);

-- ============================================================
-- TABLE 4: staff_profiles
-- ============================================================
CREATE TABLE IF NOT EXISTS staff_profiles (
  staff_id   INT PRIMARY KEY,
  department ENUM('maintenance','housekeeping','security','secretary','admin'),
  shift      ENUM('morning','evening','night'),
  FOREIGN KEY (staff_id) REFERENCES users(user_id) ON DELETE CASCADE
);

-- ============================================================
-- TABLE 5: notifications
-- ============================================================
CREATE TABLE IF NOT EXISTS notifications (
  notif_id   INT AUTO_INCREMENT PRIMARY KEY,
  user_id    INT NOT NULL,
  message    TEXT NOT NULL,
  is_read    BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE
);

-- ============================================================
-- INDEXES: for fast lookups (DBA concept)
-- ============================================================
CREATE INDEX idx_complaint_status   ON complaints(status);
CREATE INDEX idx_complaint_member  ON complaints(member_id);
CREATE INDEX idx_complaint_assigned ON complaints(assigned_to);

-- ============================================================
-- VIEW 1: pending_complaints_view
-- Used on report page and admin monitoring
-- ============================================================
CREATE OR REPLACE VIEW pending_complaints_view AS
SELECT
  c.complaint_id,
  u.full_name    AS member_name,
  u.room_number,
  u.email        AS member_email,
  c.category,
  c.title,
  c.priority,
  c.status,
  c.created_at
FROM complaints c
JOIN users u ON c.member_id = u.user_id
WHERE c.status = 'pending'
ORDER BY
  FIELD(c.priority, 'high','medium','low'),
  c.created_at ASC;

-- ============================================================
-- VIEW 2: complaint_stats_view
-- Used on admin analytics dashboard
-- ============================================================
CREATE OR REPLACE VIEW complaint_stats_view AS
SELECT
  category,
  COUNT(*)                        AS total,
  SUM(status = 'pending')         AS pending,
  SUM(status = 'in_progress')     AS in_progress,
  SUM(status = 'resolved')        AS resolved,
  SUM(status = 'rejected')        AS rejected
FROM complaints
GROUP BY category;

-- ============================================================
-- STORED PROCEDURE: assign_complaint
-- DBA demonstration: encapsulates assignment + logging
-- ============================================================
DROP PROCEDURE IF EXISTS assign_complaint;
DELIMITER $$
CREATE PROCEDURE assign_complaint(
  IN  p_complaint_id INT,
  IN  p_staff_id     INT,
  IN  p_changed_by   INT
)
BEGIN
  DECLARE v_old_status VARCHAR(20);
  DECLARE v_old_assigned INT;

  -- Get current state
  SELECT status, assigned_to
  INTO v_old_status, v_old_assigned
  FROM complaints
  WHERE complaint_id = p_complaint_id;

  -- Update assignment
  UPDATE complaints
  SET assigned_to = p_staff_id,
      status = CASE WHEN status = 'pending' THEN 'in_progress' ELSE status END
  WHERE complaint_id = p_complaint_id;

  -- Log the assignment action
  INSERT INTO complaint_logs (complaint_id, changed_by, old_status, new_status, remark)
  VALUES (
    p_complaint_id,
    p_changed_by,
    v_old_status,
    CASE WHEN v_old_status = 'pending' THEN 'in_progress' ELSE v_old_status END,
    CONCAT('Complaint assigned to staff ID: ', p_staff_id)
  );

  -- Notify the assigned staff
  INSERT INTO notifications (user_id, message)
  VALUES (
    p_staff_id,
    CONCAT('You have been assigned complaint #', p_complaint_id, '. Please review and take action.')
  );
END$$
DELIMITER ;

-- ============================================================
-- TRIGGER 1: after_complaint_update
-- Auto-logs every status change to complaint_logs
-- ============================================================
DROP TRIGGER IF EXISTS after_complaint_status_update;
DELIMITER $$
CREATE TRIGGER after_complaint_status_update
AFTER UPDATE ON complaints
FOR EACH ROW
BEGIN
  IF OLD.status != NEW.status THEN
    INSERT INTO complaint_logs (complaint_id, changed_by, old_status, new_status, remark)
    VALUES (
      NEW.complaint_id,
      COALESCE(NEW.assigned_to, NEW.member_id),
      OLD.status,
      NEW.status,
      'Status auto-logged by system trigger'
    );
  END IF;
END$$
DELIMITER ;

-- ============================================================
-- TRIGGER 2: after_complaint_insert
-- Auto-notifies admin on new complaint submission
-- ============================================================
DROP TRIGGER IF EXISTS after_complaint_insert;
DELIMITER $$
CREATE TRIGGER after_complaint_insert
AFTER INSERT ON complaints
FOR EACH ROW
BEGIN
  -- Notify all admins
  INSERT INTO notifications (user_id, message)
  SELECT user_id,
    CONCAT('New complaint submitted: "', NEW.title, '" by member ID #', NEW.member_id, ' [', UPPER(NEW.priority), ' priority]')
  FROM users
  WHERE role = 'admin' AND is_active = TRUE;
END$$
DELIMITER ;

-- ============================================================
-- MYSQL ROLE-BASED DB USERS
-- ============================================================
-- Drop if already exists (idempotent reruns)
DROP USER IF EXISTS 'society_member'@'localhost';
DROP USER IF EXISTS 'society_staff'@'localhost';
DROP USER IF EXISTS 'society_admin'@'localhost';

CREATE USER 'society_member'@'localhost' IDENTIFIED BY 'member_pass';
CREATE USER 'society_staff'@'localhost'   IDENTIFIED BY 'staff_pass';
CREATE USER 'society_admin'@'localhost'   IDENTIFIED BY 'admin_pass';

-- Member privileges
GRANT SELECT ON society_db.users TO 'society_member'@'localhost';
GRANT SELECT, INSERT ON society_db.complaints TO 'society_member'@'localhost';
GRANT SELECT ON society_db.complaint_logs TO 'society_member'@'localhost';
GRANT SELECT ON society_db.notifications TO 'society_member'@'localhost';
GRANT SELECT ON society_db.pending_complaints_view TO 'society_member'@'localhost';

-- Staff privileges
GRANT SELECT ON society_db.users TO 'society_staff'@'localhost';
GRANT SELECT, UPDATE ON society_db.complaints TO 'society_staff'@'localhost';
GRANT SELECT, INSERT ON society_db.complaint_logs TO 'society_staff'@'localhost';
GRANT SELECT ON society_db.staff_profiles TO 'society_staff'@'localhost';
GRANT SELECT ON society_db.pending_complaints_view TO 'society_staff'@'localhost';
GRANT SELECT, INSERT ON society_db.notifications TO 'society_staff'@'localhost';

-- Admin privileges (full access)
GRANT ALL PRIVILEGES ON society_db.* TO 'society_admin'@'localhost' WITH GRANT OPTION;

FLUSH PRIVILEGES;
