CREATE DATABASE IF NOT EXISTS stresser;
USE stresser;

CREATE TABLE IF NOT EXISTS plans (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(50) NOT NULL UNIQUE,
    max_time INT NOT NULL,
    max_concurrents INT NOT NULL,
    cooldown INT NOT NULL,
    is_vip BOOLEAN NOT NULL DEFAULT FALSE
);

CREATE TABLE IF NOT EXISTS users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    email VARCHAR(255) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    plan_id INT NOT NULL,
    last_attack_time TIMESTAMP NULL,
    active_attacks INT NOT NULL DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (plan_id) REFERENCES plans(id)
);

-- Insert default plans (you can add more)
INSERT INTO plans (name, max_time, max_concurrents, cooldown, is_vip) VALUES 
('Free', 30, 1, 60, FALSE),
('VIP', 300, 4, 15, TRUE)
ON DUPLICATE KEY UPDATE name=name;
