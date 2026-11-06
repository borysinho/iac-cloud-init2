CREATE TABLE IF NOT EXISTS administrators (
 id INT PRIMARY KEY AUTO_INCREMENT, username VARCHAR(100) NOT NULL UNIQUE, password_hash VARCHAR(255) NOT NULL
);
CREATE TABLE IF NOT EXISTS modules (
 id INT PRIMARY KEY AUTO_INCREMENT, name VARCHAR(150) NOT NULL,
 active TINYINT NOT NULL DEFAULT 0, active_slot TINYINT GENERATED ALWAYS AS (IF(active=1,1,NULL)) STORED UNIQUE,
 created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE IF NOT EXISTS students (
 id INT PRIMARY KEY AUTO_INCREMENT, module_id INT NOT NULL, registration VARCHAR(50) NOT NULL,
 name VARCHAR(180) NOT NULL, email VARCHAR(200) NOT NULL,
 UNIQUE(module_id, registration), UNIQUE(id,module_id), FOREIGN KEY(module_id) REFERENCES modules(id)
);
CREATE TABLE IF NOT EXISTS class_dates (
 id INT PRIMARY KEY AUTO_INCREMENT, module_id INT NOT NULL, class_date DATE NOT NULL,
 start_time TIME NOT NULL, end_time TIME NOT NULL,
 UNIQUE(module_id,class_date), UNIQUE(id,module_id), FOREIGN KEY(module_id) REFERENCES modules(id)
);
CREATE TABLE IF NOT EXISTS attendances (
 id INT PRIMARY KEY AUTO_INCREMENT, module_id INT NOT NULL, student_id INT NOT NULL, class_date_id INT NOT NULL,
 status ENUM('Presente','Falta') NOT NULL, marked_at DATETIME NULL, updated_at DATETIME NOT NULL,
 UNIQUE(student_id,class_date_id),
 FOREIGN KEY(student_id,module_id) REFERENCES students(id,module_id),
 FOREIGN KEY(class_date_id,module_id) REFERENCES class_dates(id,module_id),
 FOREIGN KEY(module_id) REFERENCES modules(id)
);
CREATE TABLE IF NOT EXISTS activities (
 id INT PRIMARY KEY AUTO_INCREMENT, module_id INT NOT NULL, actor VARCHAR(180) NOT NULL,
 student_id INT NULL, action VARCHAR(100) NOT NULL, affected VARCHAR(150) NULL,
 previous_value VARCHAR(50) NULL, new_value VARCHAR(50) NULL, created_at DATETIME NOT NULL,
 FOREIGN KEY(module_id) REFERENCES modules(id), FOREIGN KEY(student_id) REFERENCES students(id),
 INDEX(module_id,created_at)
);
