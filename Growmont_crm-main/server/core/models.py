from django.db import models
from django.contrib.auth.models import User

# Employee Model
class Employee(models.Model):
    GENDER_CHOICES = [
        ('M', 'Male'),
        ('F', 'Female'),
        ('O', 'Other')
    ]

    ROLE_CHOICES = [
        ('ADMIN', 'Admin'),
        ('EMPLOYEE', 'Employee'),
    ]

    user = models.OneToOneField(User, on_delete=models.CASCADE, null=True, blank=True, related_name='employee')
    role = models.CharField(max_length=10, choices=ROLE_CHOICES, default='EMPLOYEE')
    
    name = models.CharField(max_length=100)
    email = models.EmailField(unique=True)
    mobile_no = models.CharField(max_length=15)
    gender = models.CharField(max_length=1, choices=GENDER_CHOICES)
    dob = models.DateField()
    avatar = models.ImageField(upload_to='avatars/', null=True, blank=True)

    def __str__(self):
        return self.name


# Client Model
class Client(models.Model):
    name = models.CharField(max_length=100)
    contact_number = models.CharField(max_length=15)
    employees = models.ManyToManyField(Employee, related_name="clients")

    def __str__(self):
        return self.name


class Sale(models.Model):
    PRODUCT_CHOICES = [
        ('MF', 'Mutual Funds'),
        ('HI', 'Health Insurance'),
        ('GI', 'General Insurance'),
        ('LI', 'Life Insurance'),
        ('NCD', 'NCDs'),
        ('MLD', 'MLDs'),
        ('BOND', 'Bonds'),
        ('CFD', 'Corporate FDs'),
        ('AIF', 'AIFs'),
        ('PMS', 'PMS'),
        ('ADV', 'Advisory'),
        ('SB', 'Shares Broking'),
        ('US', 'Unlisted Shares'),
        ('RE', 'Real Estate'),
        ('LOAN', 'Loans'),
        ('WILL', 'Will Making'),
    ]

    FREQUENCY_CHOICES = [
        ('M', 'Monthly'),
        ('Q', 'Quarterly'),
        ('H', 'Half Yearly'),
        ('Y', 'Yearly'),
        ('O', 'One Time'),
    ]

    # Basic Info
    date = models.DateField()
    client_name = models.CharField(max_length=100, default='unknown')
    
    # Employee/Representative
    sales_rep = models.ForeignKey(Employee, on_delete=models.CASCADE, related_name='sales')
    
    # Product Details
    product = models.CharField(max_length=10, choices=PRODUCT_CHOICES)
    company = models.CharField(max_length=100)
    scheme = models.CharField(max_length=200)
    amount = models.DecimalField(max_digits=12, decimal_places=2)
    frequency = models.CharField(max_length=1, choices=FREQUENCY_CHOICES)
    
    # Optional
    remarks = models.TextField(blank=True)
    
    # Timestamps
    created_at = models.DateTimeField(auto_now_add=True, null=True, blank=True)
    updated_at = models.DateTimeField(auto_now=True, null=True, blank=True)

    class Meta:
        ordering = ['-date', '-created_at']

    def __str__(self):
        return f"{self.client_name} - {self.amount}"

# Interaction Model - UPDATED
class Interaction(models.Model):
    PRIORITY_CHOICES = [
        ('HIGH', 'High'),
        ('MEDIUM', 'Medium'),
        ('LOW', 'Low'),
    ]

    # Basic Info
    date = models.DateField()
    client_name = models.CharField(max_length=100, default='unknown')
    client_contact = models.CharField(max_length=15, default='0000000000')
    
    # Employee/Representative
    employee = models.ForeignKey(Employee, on_delete=models.CASCADE, related_name='interactions')
    
    # Follow-up Details
    # follow_up_date = models.DateField(null=True, blank=True)
    # follow_up_time = models.TimeField(null=True, blank=True)
    follow_up_date = models.DateField()
    follow_up_time = models.TimeField()
    # follow_up_time = models.TimeField(null=True, blank=True, default='10:00:00')
    # follow_up_date = models.DateField()
    # follow_up_time = models.TimeField(default='10:00:00')
    
    # Priority
    priority = models.CharField(max_length=10, choices=PRIORITY_CHOICES, default='MEDIUM')
    
    # Notes (optional)
    discussion_notes = models.TextField(blank=True)
    
    # Timestamps
    created_at = models.DateTimeField(auto_now_add=True, null=True, blank=True)
    updated_at = models.DateTimeField(auto_now=True, null=True, blank=True)

    class Meta:
        ordering = ['-date', '-created_at']

    def __str__(self):
        return f"{self.client_name} - {self.date}"
    

# In core/models.py

class Reminder(models.Model):
    PRIORITY_CHOICES = [
        ('HIGH', 'High Priority'),
        ('MEDIUM', 'Medium Priority'),
        ('LOW', 'Low Priority'),
    ]
    
    TYPE_CHOICES = [
        ('CORPORATE', 'Corporate Event'),
        ('PERSONAL', 'Personal'),
    ]
    
    REPEAT_CHOICES = [
        ('NONE', 'No Repeat'),
        ('DAILY', 'Daily'),
        ('WEEKLY', 'Weekly'),
        ('MONTHLY', 'Monthly'),
    ]
    
    employee = models.ForeignKey(Employee, on_delete=models.CASCADE, related_name='reminders')
    event_name = models.CharField(max_length=200)
    type = models.CharField(max_length=20, choices=TYPE_CHOICES, default='CORPORATE')
    priority = models.CharField(max_length=10, choices=PRIORITY_CHOICES, default='MEDIUM')
    date = models.DateField()
    time = models.TimeField()
    end_time = models.TimeField(null=True, blank=True)
    description = models.TextField(blank=True)
    
    is_sent = models.BooleanField(default=False) 
    
    # Repeat settings
    repeat_reminder = models.BooleanField(default=False)
    repeat_type = models.CharField(max_length=10, choices=REPEAT_CHOICES, default='NONE')
    repeat_days = models.JSONField(default=list, blank=True)  # ["Mon", "Tue", ...]
    repeat_every_day = models.BooleanField(default=False)
    
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    
    class Meta:
        ordering = ['-date', '-time']
    
    def __str__(self):
        return f"{self.event_name} - {self.date}"