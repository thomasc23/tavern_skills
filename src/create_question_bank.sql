-- Question Bank Database Schema
-- Designed for storing survey questions with multiple question types
-- Supports reusability, versioning, and flexible response options

-- ===== CORE TABLES =====

-- Question Types lookup table
CREATE TABLE question_types (
    type_id INTEGER PRIMARY KEY,
    type_name VARCHAR(50) NOT NULL,
    description TEXT,
    requires_options BOOLEAN DEFAULT TRUE,
    allows_multiple_selection BOOLEAN DEFAULT FALSE
);

-- Insert standard question types
INSERT INTO question_types (type_id, type_name, description, requires_options, allows_multiple_selection) VALUES
(1, 'likert_scale', 'Likert scale (e.g., strongly agree to strongly disagree)', TRUE, FALSE),
(2, 'multiple_choice', 'Single selection from multiple options', TRUE, FALSE),
(3, 'multiple_select', 'Multiple selections allowed (check all that apply)', TRUE, TRUE),
(4, 'open_ended', 'Free text response', FALSE, FALSE),
(5, 'numeric_scale', 'Numeric rating scale (e.g., 0-100)', FALSE, FALSE),
(6, 'ranking', 'Rank options in order of preference', TRUE, FALSE),
(7, 'message_test', 'A/B message comparison', TRUE, FALSE),
(8, 'grid', 'Matrix/grid question (multiple items, same response scale)', TRUE, FALSE);

-- Topic/Category taxonomy
CREATE TABLE topics (
    topic_id INTEGER PRIMARY KEY,
    topic_name VARCHAR(100) NOT NULL,
    parent_topic_id INTEGER REFERENCES topics(topic_id),
    description TEXT
);

INSERT INTO topics (topic_id, topic_name, parent_topic_id, description) VALUES
(1, 'Demographics', NULL, 'Basic demographic questions'),
(2, 'Political', NULL, 'Political attitudes and behavior'),
(3, 'Policy', NULL, 'Policy preference questions'),
(4, 'Housing', 3, 'Housing policy and attitudes'),
(5, 'Healthcare', 3, 'Healthcare policy'),
(6, 'Education', 3, 'Education policy'),
(7, 'Vote Choice', 2, 'Candidate and party preference'),
(8, 'Issue Priority', 2, 'Issue importance and salience');

-- Main questions table
CREATE TABLE questions (
    question_id VARCHAR(20) PRIMARY KEY,
    question_text TEXT NOT NULL,
    question_type_id INTEGER NOT NULL REFERENCES question_types(type_id),
    topic_id INTEGER REFERENCES topics(topic_id),

    -- Conditional display logic
    parent_question_id VARCHAR(20) REFERENCES questions(question_id),
    display_condition TEXT, -- e.g., "parent_response IN ('Yes', 'Maybe')"

    -- Metadata
    created_date DATE,
    last_used_date DATE,
    times_used INTEGER DEFAULT 0,

    -- Question-specific parameters (stored as JSON for flexibility)
    parameters JSON, -- e.g., {"min": 0, "max": 100, "step": 1} for numeric scales

    -- Versioning
    is_active BOOLEAN DEFAULT TRUE,
    version INTEGER DEFAULT 1,
    notes TEXT
);

-- Response options (for questions that have predefined options)
CREATE TABLE response_options (
    option_id INTEGER PRIMARY KEY,
    question_id VARCHAR(20) NOT NULL REFERENCES questions(question_id),
    option_text TEXT NOT NULL,
    option_value VARCHAR(100), -- coded value for analysis
    display_order INTEGER NOT NULL,
    is_exclusive BOOLEAN DEFAULT FALSE, -- e.g., "None of the above"

    UNIQUE(question_id, display_order)
);

-- Question tags (for flexible categorization beyond topic hierarchy)
CREATE TABLE tags (
    tag_id INTEGER PRIMARY KEY,
    tag_name VARCHAR(50) NOT NULL UNIQUE
);

CREATE TABLE question_tags (
    question_id VARCHAR(20) REFERENCES questions(question_id),
    tag_id INTEGER REFERENCES tags(tag_id),
    PRIMARY KEY (question_id, tag_id)
);

-- Survey deployment tracking
CREATE TABLE surveys (
    survey_id INTEGER PRIMARY KEY,
    survey_name VARCHAR(200) NOT NULL,
    field_start_date DATE,
    field_end_date DATE,
    sample_size INTEGER,
    population TEXT,
    notes TEXT
);

CREATE TABLE survey_questions (
    survey_id INTEGER REFERENCES surveys(survey_id),
    question_id VARCHAR(20) REFERENCES questions(question_id),
    display_order INTEGER NOT NULL,
    is_required BOOLEAN DEFAULT FALSE,

    PRIMARY KEY (survey_id, question_id)
);

-- ===== INDEXES FOR PERFORMANCE =====

CREATE INDEX idx_questions_topic ON questions(topic_id);
CREATE INDEX idx_questions_type ON questions(question_type_id);
CREATE INDEX idx_questions_active ON questions(is_active);
CREATE INDEX idx_response_options_question ON response_options(question_id);
CREATE INDEX idx_survey_questions_survey ON survey_questions(survey_id);

-- ===== VIEWS FOR COMMON QUERIES =====

-- View: Questions with full metadata
CREATE VIEW v_questions_full AS
SELECT
    q.question_id,
    q.question_text,
    qt.type_name AS question_type,
    t.topic_name AS topic,
    q.times_used,
    q.last_used_date,
    q.is_active,
    q.version
FROM questions q
LEFT JOIN question_types qt ON q.question_type_id = qt.type_id
LEFT JOIN topics t ON q.topic_id = t.topic_id;

-- View: Questions with their response options
CREATE VIEW v_questions_with_options AS
SELECT
    q.question_id,
    q.question_text,
    qt.type_name,
    ro.option_text,
    ro.option_value,
    ro.display_order
FROM questions q
JOIN question_types qt ON q.question_type_id = qt.type_id
LEFT JOIN response_options ro ON q.question_id = ro.question_id
ORDER BY q.question_id, ro.display_order;

-- ===== SAMPLE DATA INSERTION =====

-- Example: Demographic gender question
INSERT INTO questions (question_id, question_text, question_type_id, topic_id, created_date, times_used)
VALUES ('DEMO_001', 'Please select your gender:', 2, 1, '2025-01-01', 0);

INSERT INTO response_options (option_id, question_id, option_text, option_value, display_order) VALUES
(1, 'DEMO_001', 'Male', '1', 1),
(2, 'DEMO_001', 'Female', '2', 2),
(3, 'DEMO_001', 'Non-binary', '3', 3),
(4, 'DEMO_001', 'Prefer not to say', '99', 4);

-- Example: Likert scale policy question
INSERT INTO questions (question_id, question_text, question_type_id, topic_id, created_date)
VALUES ('POLICY_001', 'Do you support or oppose requiring local governments to approve housing projects that meet state building standards?', 1, 4, '2025-01-01');

INSERT INTO response_options (option_id, question_id, option_text, option_value, display_order) VALUES
(5, 'POLICY_001', 'Strongly support', '1', 1),
(6, 'POLICY_001', 'Somewhat support', '2', 2),
(7, 'POLICY_001', 'Somewhat oppose', '3', 3),
(8, 'POLICY_001', 'Strongly oppose', '4', 4),
(9, 'POLICY_001', 'Not sure', '9', 5);

-- Example: Open-ended question
INSERT INTO questions (question_id, question_text, question_type_id, topic_id, created_date)
VALUES ('OPEN_001', 'In your own words, what is the most important issue facing your community right now?', 4, NULL, '2025-01-01');

-- Example: Multiple select question
INSERT INTO questions (question_id, question_text, question_type_id, topic_id, created_date)
VALUES ('MULTI_001', 'Which of the following issues are most important to you? (Select all that apply)', 3, 8, '2025-01-01');

INSERT INTO response_options (option_id, question_id, option_text, option_value, display_order) VALUES
(10, 'MULTI_001', 'Economy and jobs', 'economy', 1),
(11, 'MULTI_001', 'Healthcare', 'healthcare', 2),
(12, 'MULTI_001', 'Education', 'education', 3),
(13, 'MULTI_001', 'Climate change', 'climate', 4),
(14, 'MULTI_001', 'Immigration', 'immigration', 5);

-- Example: Conditional follow-up question
INSERT INTO questions (question_id, question_text, question_type_id, topic_id, parent_question_id, display_condition, created_date)
VALUES ('VOTE_001A', 'Who did you vote for in the 2024 presidential election?', 2, 7, 'VOTE_001', "response = 'Yes, I voted'", '2025-01-01');

-- Add some tags
INSERT INTO tags (tag_id, tag_name) VALUES
(1, 'core_demographic'),
(2, 'political_behavior'),
(3, 'housing_policy'),
(4, 'message_testing'),
(5, 'experimental');

INSERT INTO question_tags (question_id, tag_id) VALUES
('DEMO_001', 1),
('POLICY_001', 3),
('MULTI_001', 2);
