# Inside db.py
import mysql.connector

def get_db_connection():  # <-- Make sure this function name matches!
    connection = mysql.connector.connect(
        host="localhost",
        user="root",
        password="AstRick@45",
        database="smartsplit_db"
    )
    return connection
