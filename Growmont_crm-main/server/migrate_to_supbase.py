"""
SQLite to Supabase PostgreSQL Migration Script - FIXED VERSION
Place this in: server/backend/migrate_to_supabase.py
Run with: python migrate_to_supabase.py

Fixes: Properly handles sqlite3.Row objects without using .get() method
"""

import os
import sys
import django

# Setup Django
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'backend.settings')
django.setup()

import sqlite3
from django.contrib.auth.models import User
from core.models import Employee, Client, Sale, Interaction
from django.db import transaction

# Path to SQLite backup
SQLITE_DB_PATH = 'db.sqlite3.backup'

def safe_get(row, key, default=''):
    """Safely get value from sqlite3.Row object"""
    try:
        value = row[key]
        return value if value is not None else default
    except (KeyError, IndexError):
        return default

def test_connection():
    """Test Supabase connection"""
    print("🔌 Testing Supabase connection...")
    try:
        from django.db import connection
        with connection.cursor() as cursor:
            cursor.execute("SELECT version();")
            version = cursor.fetchone()[0]
            print(f"✅ Connected to PostgreSQL: {version}\n")
            return True
    except Exception as e:
        print(f"❌ Connection failed: {e}")
        print("\nTroubleshooting:")
        print("1. Check DATABASE_URL in .env file")
        print("2. Verify Supabase credentials")
        print("3. Ensure migrations are run: python manage.py migrate")
        return False

def migrate_users():
    """Migrate users from SQLite to Supabase"""
    print("👥 Migrating users...")
    
    conn = sqlite3.connect(SQLITE_DB_PATH)
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()
    
    cursor.execute('SELECT * FROM auth_user ORDER BY id')
    users = cursor.fetchall()
    
    count = 0
    for user_row in users:
        with transaction.atomic():
            user, created = User.objects.update_or_create(
                username=user_row['username'],
                defaults={
                    'email': safe_get(user_row, 'email', ''),
                    'password': user_row['password'],
                    'is_staff': user_row['is_staff'],
                    'is_active': user_row['is_active'],
                    'is_superuser': user_row['is_superuser'],
                    'first_name': safe_get(user_row, 'first_name', ''),
                    'last_name': safe_get(user_row, 'last_name', ''),
                    'date_joined': user_row['date_joined'],
                }
            )
            status = "✅" if created else "🔄"
            print(f"  {status} {user.username}")
            count += 1
    
    conn.close()
    print(f"  Total: {count} users\n")

def migrate_employees():
    """Migrate employees from SQLite to Supabase"""
    print("👔 Migrating employees...")
    
    conn = sqlite3.connect(SQLITE_DB_PATH)
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()
    
    cursor.execute('SELECT * FROM core_employee ORDER BY id')
    employees = cursor.fetchall()
    
    count = 0
    for emp_row in employees:
        with transaction.atomic():
            user = None
            user_id = safe_get(emp_row, 'user_id', None)
            
            if user_id:
                try:
                    user = User.objects.get(id=user_id)
                except User.DoesNotExist:
                    # Try to find by email
                    try:
                        user = User.objects.get(email=emp_row['email'])
                    except User.DoesNotExist:
                        print(f"  ⚠️  User not found for employee: {emp_row['name']}")
            
            emp, created = Employee.objects.update_or_create(
                email=emp_row['email'],
                defaults={
                    'user': user,
                    'name': emp_row['name'],
                    'mobile_no': emp_row['mobile_no'],
                    'gender': emp_row['gender'],
                    'dob': emp_row['dob'],
                    'role': emp_row['role'],
                    'avatar': safe_get(emp_row, 'avatar', ''),
                }
            )
            status = "✅" if created else "🔄"
            print(f"  {status} {emp.name} ({emp.role})")
            count += 1
    
    conn.close()
    print(f"  Total: {count} employees\n")

def migrate_clients():
    """Migrate clients from SQLite to Supabase"""
    print("🏢 Migrating clients...")
    
    conn = sqlite3.connect(SQLITE_DB_PATH)
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()
    
    cursor.execute('SELECT * FROM core_client ORDER BY id')
    clients = cursor.fetchall()
    
    client_map = {}
    count = 0
    
    for client_row in clients:
        with transaction.atomic():
            client, created = Client.objects.get_or_create(
                name=client_row['name'],
                contact_number=safe_get(client_row, 'contact_number', ''),
            )
            client_map[client_row['id']] = client
            status = "✅" if created else "🔄"
            print(f"  {status} {client.name}")
            count += 1
    
    print(f"  Total: {count} clients")
    
    # Migrate many-to-many relationships
    print("  📎 Linking clients with employees...")
    try:
        cursor.execute('SELECT * FROM core_client_employees')
        relationships = cursor.fetchall()
        
        link_count = 0
        for rel in relationships:
            with transaction.atomic():
                try:
                    client = client_map.get(rel['client_id'])
                    employee = Employee.objects.get(id=rel['employee_id'])
                    if client and employee:
                        client.employees.add(employee)
                        link_count += 1
                except Employee.DoesNotExist:
                    pass
        print(f"  ✅ Created {link_count} client-employee links\n")
    except sqlite3.OperationalError:
        print("  ⚠️  No client-employee relationships found\n")
    
    conn.close()
    return client_map

def migrate_sales(client_map):
    """Migrate sales from SQLite to Supabase"""
    print("💰 Migrating sales...")
    
    conn = sqlite3.connect(SQLITE_DB_PATH)
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()
    
    cursor.execute('SELECT * FROM core_sale ORDER BY id')
    sales = cursor.fetchall()
    
    count = 0
    errors = 0
    
    for sale_row in sales:
        with transaction.atomic():
            try:
                # Get client
                client = client_map.get(sale_row['client_id'])
                if not client:
                    try:
                        client = Client.objects.get(id=sale_row['client_id'])
                    except Client.DoesNotExist:
                        print(f"  ❌ Client {sale_row['client_id']} not found")
                        errors += 1
                        continue
                
                # Get sales rep
                try:
                    sales_rep = Employee.objects.get(id=sale_row['sales_rep_id'])
                except Employee.DoesNotExist:
                    print(f"  ❌ Employee {sale_row['sales_rep_id']} not found")
                    errors += 1
                    continue
                
                # Create or update sale
                sale, created = Sale.objects.update_or_create(
                    client=client,
                    date=sale_row['date'],
                    sales_rep=sales_rep,
                    amount=sale_row['amount'],
                    defaults={
                        'product': sale_row['product'],
                        'company': sale_row['company'],
                        'scheme': safe_get(sale_row, 'scheme', ''),
                        'frequency': sale_row['frequency'],
                        'remarks': safe_get(sale_row, 'remarks', ''),
                    }
                )
                status = "✅" if created else "🔄"
                print(f"  {status} {client.name} - ${sale.amount}")
                count += 1
                
            except Exception as e:
                print(f"  ❌ Error: {e}")
                errors += 1
    
    conn.close()
    print(f"  Total: {count} sales (Errors: {errors})\n")

def migrate_interactions(client_map):
    """Migrate interactions from SQLite to Supabase"""
    print("📞 Migrating interactions...")
    
    conn = sqlite3.connect(SQLITE_DB_PATH)
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()
    
    cursor.execute('SELECT * FROM core_interaction ORDER BY id')
    interactions = cursor.fetchall()
    
    count = 0
    errors = 0
    
    for int_row in interactions:
        with transaction.atomic():
            try:
                # Get client
                client = client_map.get(int_row['client_id'])
                if not client:
                    try:
                        client = Client.objects.get(id=int_row['client_id'])
                    except Client.DoesNotExist:
                        print(f"  ❌ Client {int_row['client_id']} not found")
                        errors += 1
                        continue
                
                # Get employee
                try:
                    employee = Employee.objects.get(id=int_row['employee_id'])
                except Employee.DoesNotExist:
                    print(f"  ❌ Employee {int_row['employee_id']} not found")
                    errors += 1
                    continue
                
                # Create or update interaction
                interaction, created = Interaction.objects.update_or_create(
                    client=client,
                    employee=employee,
                    date=int_row['date'],
                    defaults={
                        'discussion_notes': safe_get(int_row, 'discussion_notes', ''),
                        'next_follow_up': int_row['next_follow_up'],
                    }
                )
                status = "✅" if created else "🔄"
                print(f"  {status} {client.name} - {int_row['date']}")
                count += 1
                
            except Exception as e:
                print(f"  ❌ Error: {e}")
                errors += 1
    
    conn.close()
    print(f"  Total: {count} interactions (Errors: {errors})\n")

def print_summary():
    """Print migration summary"""
    print("="*60)
    print("📊 FINAL SUMMARY")
    print("="*60)
    print(f"👥 Users:        {User.objects.count()}")
    print(f"👔 Employees:    {Employee.objects.count()}")
    print(f"🏢 Clients:      {Client.objects.count()}")
    print(f"💰 Sales:        {Sale.objects.count()}")
    print(f"📞 Interactions: {Interaction.objects.count()}")
    print("="*60)

def main():
    """Main migration function"""
    print("\n" + "="*60)
    print("🚀 SUPABASE POSTGRESQL MIGRATION")
    print("="*60 + "\n")
    
    # Check if SQLite backup exists
    if not os.path.exists(SQLITE_DB_PATH):
        print(f"❌ SQLite backup not found: {SQLITE_DB_PATH}")
        print(f"\nCreate it first:")
        print(f"  cp db.sqlite3 {SQLITE_DB_PATH}")
        return
    
    # Test Supabase connection
    if not test_connection():
        return
    
    try:
        # Run migrations in order
        migrate_users()
        migrate_employees()
        client_map = migrate_clients()
        migrate_sales(client_map)
        migrate_interactions(client_map)
        
        # Print summary
        print_summary()
        
        print("\n✅ Migration completed successfully!")
        print("\n📍 Next steps:")
        print("1. Verify data in Supabase Dashboard:")
        print("   https://app.supabase.com/project/YOUR-PROJECT/editor")
        print("2. Create superuser: python manage.py createsuperuser")
        print("3. Test Django admin: python manage.py runserver")
        print("4. Test API endpoints")
        print("\n" + "="*60 + "\n")
        
    except Exception as e:
        print(f"\n❌ Migration failed: {e}")
        import traceback
        traceback.print_exc()
        print("\n💡 Troubleshooting:")
        print("1. Check your .env file has correct DATABASE_URL")
        print("2. Verify Supabase credentials")
        print("3. Run: python manage.py migrate")
        print("4. Check Supabase dashboard for errors")

if __name__ == '__main__':
    main()