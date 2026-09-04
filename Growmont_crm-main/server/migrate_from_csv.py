import os
import django
import csv
from django.db import transaction

# --- Setup Django environment ---
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'backend.settings')
django.setup()  # MUST come before importing models

# --- Import models AFTER setup ---
from django.contrib.auth.models import User
from core.models import Employee, Client, Sale, Interaction

# --- Helper function ---
def safe_get(row, key, default=''):
    return row.get(key, default)


def migrate_users():
    print("👥 Migrating users...")
    with open('csv/auth_user.csv', newline='', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        count = 0
        for row in reader:
            with transaction.atomic():
                user, created = User.objects.update_or_create(
                    username=row['username'],
                    defaults={
                        'email': safe_get(row, 'email'),
                        'password': safe_get(row, 'password'),
                        'is_staff': row['is_staff'].lower() in ['true', '1'],
                        'is_active': row['is_active'].lower() in ['true', '1'],
                        'is_superuser': row['is_superuser'].lower() in ['true', '1'],
                        'first_name': safe_get(row, 'first_name'),
                        'last_name': safe_get(row, 'last_name'),
                        'date_joined': safe_get(row, 'date_joined'),
                    }
                )
                count += 1
    print(f"✅ Total users migrated: {count}\n")


def migrate_employees():
    print("👔 Migrating employees...")
    with open('csv/core_employee.csv', newline='', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        count = 0
        for row in reader:
            user = None
            # Try linking user by username/email if exists
            try:
                user = User.objects.get(username=row['user_id'])
            except User.DoesNotExist:
                try:
                    user = User.objects.get(email=row['email'])
                except User.DoesNotExist:
                    pass

            with transaction.atomic():
               
                emp, created = Employee.objects.update_or_create(
                    id=row['id'],
                    defaults={
                        'user': user,
                        'email': row['email'],
                        'name': row['name'],
                        'mobile_no': row['mobile_no'],
                        'gender': row['gender'],
                        'dob': row['dob'],
                        'role': row['role'],
                        'avatar': safe_get(row, 'avatar'),
                    }
                )
                count += 1
    print(f"✅ Total employees migrated: {count}\n")


def migrate_clients():
    print("🏢 Migrating clients...")
    client_map = {}
    with open('csv/core_client.csv', newline='', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        count = 0
        for row in reader:
            with transaction.atomic():
                client, created = Client.objects.update_or_create(
                    name=row['name'],
                    defaults={
                        'contact_number': safe_get(row, 'contact_number'),
                    }
                )
                client_map[row['id']] = client
                count += 1
    print(f"✅ Total clients migrated: {count}\n")
    return client_map


def migrate_sales():
    print("💰 Migrating sales...")
    with open('csv/core_sale.csv', newline='', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        count = 0
        errors = 0
        for row in reader:
            try:
                sales_rep = Employee.objects.get(id=row['sales_rep_id'])
                with transaction.atomic():
                    Sale.objects.update_or_create(
                        id=row['id'],
                        defaults={
                            'date': row['date'],
                            'client_name': row['client_name'],
                            'sales_rep': sales_rep,
                            'product': row['product'],
                            'company': row['company'],
                            'scheme': safe_get(row, 'scheme'),
                            'amount': row['amount'],
                            'frequency': row['frequency'],
                            'remarks': safe_get(row, 'remarks'),
                        }
                    )
                    count += 1
            except Exception as e:
                print(f"❌ Error migrating sale: {e}")
                errors += 1
    print(f"✅ Sales migrated: {count}, Errors: {errors}\n")


def migrate_interactions():
    print("📞 Migrating interactions...")
    with open('csv/core_interaction.csv', newline='', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        count = 0
        errors = 0
        for row in reader:
            try:
                employee = Employee.objects.get(id=row['employee_id'])
                with transaction.atomic():
                    Interaction.objects.update_or_create(
                        id=row['id'],
                        defaults={
                            'date': row['date'],
                            'client_name': row['client_name'],
                            'client_contact': row['client_contact'],
                            'employee': employee,
                            'follow_up_date': row['follow_up_date'],
                            'follow_up_time': row['follow_up_time'],
                            'priority': row['priority'],
                            'discussion_notes': safe_get(row, 'discussion_notes'),
                        }
                    )
                    count += 1
            except Exception as e:
                print(f"❌ Error migrating interaction: {e}")
                errors += 1
    print(f"✅ Interactions migrated: {count}, Errors: {errors}\n")


def main():
    print("="*60)
    print("🚀 MIGRATION FROM SUPABASE CSV TO RENDER DB")
    print("="*60 + "\n")

    migrate_users()
    migrate_employees()
    client_map = migrate_clients()
    migrate_sales()
    migrate_interactions()

    print("\n✅ Migration complete!\n")
    print("Users:", User.objects.count())
    print("Employees:", Employee.objects.count())
    print("Clients:", Client.objects.count())
    print("Sales:", Sale.objects.count())
    print("Interactions:", Interaction.objects.count())


if __name__ == "__main__":
    main()