#!/usr/bin/env python3
"""
Populate Question Bank from questions.csv
Loads the survey questions into the database schema
"""

import sqlite3
import csv
import re
from datetime import datetime

# Database file
DB_FILE = "tavern_files/question_bank.db"
CSV_FILE = "tavern_files/questions.csv"

def classify_question_type(question_text, response_options):
    """
    Infer question type from text and response options
    """
    text_lower = question_text.lower()

    # Open-ended
    if response_options == "[Open-ended response]":
        return 4  # open_ended

    # Numeric scale
    if "[Numeric scale" in response_options:
        return 5  # numeric_scale

    # Ranking
    if "rank" in text_lower and "order" in text_lower:
        return 6  # ranking

    # Message test (A/B comparison)
    if "message a" in text_lower and "message b" in text_lower:
        return 7  # message_test

    # Multiple select
    if "select all" in text_lower or "check all" in text_lower:
        return 3  # multiple_select

    # Check for Likert patterns
    likert_patterns = [
        "support or oppose",
        "approve or disapprove",
        "favorable or unfavorable",
        "agree or disagree",
        "priority"
    ]

    for pattern in likert_patterns:
        if pattern in text_lower:
            return 1  # likert_scale

    # Default to multiple choice
    return 2  # multiple_choice


def infer_topic(question_text):
    """
    Infer topic from question text
    """
    text_lower = question_text.lower()

    # Demographics (questions 1-3, 15-23)
    if any(word in text_lower for word in ["gender", "education", "race", "ethnicity", "employment", "relationship"]):
        return 1  # Demographics

    # Vote choice and political behavior
    if any(word in text_lower for word in ["vote", "voting", "election", "candidate", "democrat", "republican"]):
        return 7  # Vote Choice

    # Housing
    if any(word in text_lower for word in ["housing", "home", "rent", "zoning", "development", "neighborhood"]):
        return 4  # Housing

    # General policy
    return 3  # Policy


def parse_response_options(options_str):
    """
    Parse pipe-delimited response options
    """
    if options_str in ["[Open-ended response]", "[Numeric scale 0-100]"]:
        return []

    # Split by pipe and clean
    options = [opt.strip() for opt in options_str.split("|")]
    return options


def main():
    # Create database
    conn = sqlite3.connect(DB_FILE)
    cursor = conn.cursor()

    # Read and execute schema
    print("Creating database schema...")
    with open("src/create_question_bank.sql", "r") as f:
        schema_sql = f.read()
        cursor.executescript(schema_sql)

    conn.commit()

    # Load questions from CSV
    print(f"\nLoading questions from {CSV_FILE}...")

    with open(CSV_FILE, "r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        questions_data = list(reader)

    print(f"Found {len(questions_data)} questions")

    # Insert questions
    option_id_counter = 1000  # Start high to avoid conflicts with sample data

    for idx, row in enumerate(questions_data, 1):
        question_id = row["question_id"]
        question_text = row["question_text"]
        response_options = row["response_options"]
        field_date = row.get("field_date", "")

        # Classify question
        question_type_id = classify_question_type(question_text, response_options)
        topic_id = infer_topic(question_text)

        # Parse field date
        try:
            field_date_obj = datetime.strptime(field_date, "%Y-%m-%d") if field_date else None
        except:
            field_date_obj = None

        # Insert question
        cursor.execute("""
            INSERT INTO questions (
                question_id, question_text, question_type_id, topic_id,
                created_date, last_used_date, times_used, is_active, version
            ) VALUES (?, ?, ?, ?, ?, ?, 0, 1, 1)
        """, (
            question_id,
            question_text,
            question_type_id,
            topic_id,
            field_date_obj,
            field_date_obj
        ))

        # Insert response options
        options = parse_response_options(response_options)

        for display_order, option_text in enumerate(options, 1):
            # Determine option value (coded value)
            option_value = str(display_order)

            cursor.execute("""
                INSERT INTO response_options (
                    option_id, question_id, option_text, option_value, display_order
                ) VALUES (?, ?, ?, ?, ?)
            """, (
                option_id_counter,
                question_id,
                option_text,
                option_value,
                display_order
            ))

            option_id_counter += 1

        if idx % 10 == 0:
            print(f"  Processed {idx} questions...")

    conn.commit()

    # Print summary statistics
    print("\n===== DATABASE SUMMARY =====")

    cursor.execute("SELECT COUNT(*) FROM questions")
    total_questions = cursor.fetchone()[0]
    print(f"\nTotal questions: {total_questions}")

    cursor.execute("""
        SELECT qt.type_name, COUNT(*) as count
        FROM questions q
        JOIN question_types qt ON q.question_type_id = qt.type_id
        GROUP BY qt.type_name
        ORDER BY count DESC
    """)

    print("\nQuestions by type:")
    for type_name, count in cursor.fetchall():
        print(f"  {type_name}: {count}")

    cursor.execute("""
        SELECT t.topic_name, COUNT(*) as count
        FROM questions q
        LEFT JOIN topics t ON q.topic_id = t.topic_id
        GROUP BY t.topic_name
        ORDER BY count DESC
    """)

    print("\nQuestions by topic:")
    for topic_name, count in cursor.fetchall():
        topic_display = topic_name if topic_name else "(None)"
        print(f"  {topic_display}: {count}")

    cursor.execute("SELECT COUNT(*) FROM response_options")
    total_options = cursor.fetchone()[0]
    print(f"\nTotal response options: {total_options}")

    # Show some example queries
    print("\n===== EXAMPLE QUERIES =====")

    print("\n1. All housing-related questions:")
    cursor.execute("""
        SELECT question_id, SUBSTR(question_text, 1, 80) || '...' as question_preview
        FROM questions
        WHERE topic_id = 4
        LIMIT 5
    """)

    for qid, preview in cursor.fetchall():
        print(f"  {qid}: {preview}")

    print("\n2. All Likert scale questions:")
    cursor.execute("""
        SELECT COUNT(*) FROM questions WHERE question_type_id = 1
    """)
    likert_count = cursor.fetchone()[0]
    print(f"  Found {likert_count} Likert scale questions")

    print("\n3. All multiple select (check all that apply) questions:")
    cursor.execute("""
        SELECT question_id, SUBSTR(question_text, 1, 80) || '...' as question_preview
        FROM questions
        WHERE question_type_id = 3
        LIMIT 3
    """)

    for qid, preview in cursor.fetchall():
        print(f"  {qid}: {preview}")

    conn.close()

    print(f"\n===== SUCCESS =====")
    print(f"Question bank created: {DB_FILE}")
    print(f"You can query it with: sqlite3 {DB_FILE}")

if __name__ == "__main__":
    main()
