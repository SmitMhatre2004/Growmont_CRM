from django.contrib import admin
from .models import Employee, Client, Sale, Interaction

admin.site.register(Employee)
admin.site.register(Client)
admin.site.register(Sale)
admin.site.register(Interaction)
