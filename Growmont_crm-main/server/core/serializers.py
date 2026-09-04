from rest_framework import serializers
from .models import Employee, Client, Sale, Interaction, Reminder

class EmployeeSerializer(serializers.ModelSerializer):
    clients_count = serializers.IntegerField(read_only=True)
    sales_count = serializers.IntegerField(read_only=True)
    interactions_count = serializers.IntegerField(read_only=True)

    class Meta:
        model = Employee
        fields = [
            'id',
            'name',
            'email',
            'mobile_no',
            'gender',
            'dob',
            'avatar',
            'clients_count',
            'sales_count',
            'interactions_count',
            'role',
        ]


class ClientSerializer(serializers.ModelSerializer):
    class Meta:
        model = Client
        fields = '__all__'

# ============ UPDATED INTERACTION SERIALIZERS ============
class InteractionCreateSerializer(serializers.ModelSerializer):
    
    # follow_up_date = serializers.DateField(required=False, allow_null=True)
    # follow_up_time = serializers.TimeField(required=False, allow_null=True)
    follow_up_date = serializers.DateField(required=True, allow_null=False)
    follow_up_time = serializers.TimeField(required=True, allow_null=False)

    class Meta:
        model = Interaction
        fields = [
            'date',
            'client_name',
            'client_contact',
            'employee',
            'follow_up_date',
            'follow_up_time',
            'priority',
            'discussion_notes',
        ]

    def validate(self, data):
        # follow_up_date = data.get('follow_up_date')
        # date = data.get('date')
        interaction_date = data.get('date')
        follow_up_date = data.get('follow_up_date')

        # Follow-up date is optional.
        # Only validate it when the user actually provides one.
        if (
            interaction_date is not None
            and follow_up_date is not None
            and follow_up_date < interaction_date
        ):
            raise serializers.ValidationError({
                'follow_up_date':
                    'Follow-up date cannot be before interaction date.'
            })

        return data

        # Only validate if follow_up_date exists
        # if follow_up_date and date:
        #     if follow_up_date < date:
        #         raise serializers.ValidationError({
        #             'follow_up_date': 'Follow-up date cannot be before interaction date'
        #         })

        # return data


class InteractionSerializer(serializers.ModelSerializer):
    """Serializer for reading interactions with employee details"""
    employee_name = serializers.CharField(source='employee.name', read_only=True)
    employee_id = serializers.IntegerField(source='employee.id', read_only=True)
    priority_display = serializers.CharField(source='get_priority_display', read_only=True)

    class Meta:
        model = Interaction
        fields = [
            'id',
            'date',
            'client_name',
            'client_contact',
            'employee',
            'employee_name',
            'employee_id',
            'follow_up_date',
            'follow_up_time',
            'priority',
            'priority_display',
            'discussion_notes',
            'created_at',
            'updated_at',
        ]

class SaleCreateSerializer(serializers.ModelSerializer):
    class Meta:
        model = Sale
        fields = [
            'date',
            'client_name',
            'sales_rep',
            'product',
            'company',
            'scheme',
            'amount',
            'frequency',
            'remarks',
        ]


class SaleSerializer(serializers.ModelSerializer):
    sales_rep_name = serializers.CharField(source='sales_rep.name', read_only=True)
    sales_rep_id = serializers.IntegerField(source='sales_rep.id', read_only=True)
    product_display = serializers.CharField(source='get_product_display', read_only=True)
    frequency_display = serializers.CharField(source='get_frequency_display', read_only=True)

    class Meta:
        model = Sale
        fields = [
            'id',
            'date',
            'client_name',
            'sales_rep',
            'sales_rep_name',
            'sales_rep_id',
            'product',
            'product_display',
            'company',
            'scheme',
            'amount',
            'frequency',
            'frequency_display',
            'remarks',
            'created_at',
            'updated_at',
        ]


# In core/serializers.py
class ReminderSerializer(serializers.ModelSerializer):
    employee_name = serializers.CharField(source='employee.name', read_only=True)
    
    class Meta:
        model = Reminder
        fields = [
            'id', 'employee', 'employee_name', 'event_name', 'type', 
            'priority', 'date', 'time', 'end_time', 'description',
            'repeat_reminder', 'repeat_type', 'repeat_days', 'repeat_every_day',
            'created_at', 'updated_at'
        ]