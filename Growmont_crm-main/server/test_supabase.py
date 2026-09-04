"""
Test Supabase Connection
Place in: server/backend/test_supabase.py
Run with: python test_supabase.py
"""

import os
import django

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'backend.settings')
django.setup()

from django.db import connection

def test_connection():
    """Test Supabase PostgreSQL connection"""
    print("🔌 Testing Supabase connection...\n")
    
    try:
        with connection.cursor() as cursor:
            # Test basic query
            cursor.execute("SELECT version();")
            version = cursor.fetchone()[0]
            print(" Connection successful!")
            print(f"PostgreSQL version: {version}\n")
            
            # Check if tables exist
            cursor.execute("""
                SELECT table_name 
                FROM information_schema.tables 
                WHERE table_schema = 'public' 
                ORDER BY table_name;
            """)
            tables = cursor.fetchall()
            
            if tables:
                print(f"📋 Found {len(tables)} tables:")
                for table in tables:
                    cursor.execute(f"SELECT COUNT(*) FROM {table[0]};")
                    count = cursor.fetchone()[0]
                    print(f"  ✓ {table[0]}: {count} rows")
            else:
                print("  No tables found. Run: python manage.py migrate")
            
            print("\n" + "="*50)
            print(" Supabase is ready to use!")
            print("="*50)
            return True
            
    except Exception as e:
        print(f" Connection failed: {e}\n")
        print("Troubleshooting:")
        print("1. Check your .env file:")
        print("   DATABASE_URL=postgresql://postgres:[PASSWORD]@db.xxxxx.supabase.co:5432/postgres")
        print("2. Verify credentials in Supabase Dashboard → Settings → Database")
        print("3. Make sure you ran: pip install psycopg2-binary")
        print("4. Check if DATABASE_URL is correctly formatted")
        return False

if __name__ == '__main__':
    test_connection()