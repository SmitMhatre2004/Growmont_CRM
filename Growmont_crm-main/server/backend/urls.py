# """
# URL configuration for backend project.

# The `urlpatterns` list routes URLs to views. For more information please see:
#     https://docs.djangoproject.com/en/6.0/topics/http/urls/
# Examples:
# Function views
#     1. Add an import:  from my_app import views
#     2. Add a URL to urlpatterns:  path('', views.home, name='home')
# Class-based views
#     1. Add an import:  from other_app.views import Home
#     2. Add a URL to urlpatterns:  path('', Home.as_view(), name='home')
# Including another URLconf
#     1. Import the include() function: from django.urls import include, path
#     2. Add a URL to urlpatterns:  path('blog/', include('blog.urls'))
# """

"""
URL configuration for backend project.
"""
from django.contrib import admin
from django.urls import path, include
from rest_framework_simplejwt.views import TokenRefreshView
from django.conf import settings
from django.conf.urls.static import static

from core.views import (
    health_check, protected_view, LogoutView, 
    sales_list, interactions_list,
    employee_clients, employee_detail, employee_sales, employees_list, update_employee, delete_employee,   
    export_sales_excel, export_interactions_excel, 
    import_sales_excel, import_interactions_excel,
    update_interaction, update_sale, 
    export_interactions_excel_filtered, export_sales_excel_filtered,
    change_password, current_user, forgot_password,
    create_sale, create_interaction, delete_sale, delete_interaction,employees_for_dropdown,
    CustomTokenObtainPairView, delete_reminder, create_reminder, reminders_list, update_reminder
)


urlpatterns = [
    path('admin/', admin.site.urls),

    # Health & Test
    path('api/health/', health_check),
    path("api/protected/", protected_view),
    
    # Auth
    path('api/auth/login/', CustomTokenObtainPairView.as_view(), name='token_obtain_pair'),
    path('api/auth/refresh/', TokenRefreshView.as_view(), name='token_refresh'),
    path("api/auth/logout/", LogoutView.as_view(), name="logout"),
    path("api/me/", current_user),
    path("api/auth/password/change/", change_password),
    path("api/auth/password/forgot/", forgot_password),

    # Employees
    path('api/employees/', employees_list),
    path('api/employees/<int:id>/', employee_detail),
    path('api/employees/<int:id>/update/', update_employee),  # PUT - ADD THIS
    path('api/employees/<int:id>/delete/', delete_employee),  # DELETE - ADD THIS
    path('api/employees/<int:id>/clients/', employee_clients),
    path('api/employees/<int:id>/sales/', employee_sales),

    # Sales
    path('api/sales/', sales_list),
    path('api/sales/create/', create_sale),
    path('api/sales/<int:pk>/update/', update_sale),
    path('api/sales/<int:pk>/delete/', delete_sale),

    # Interactions
    path('api/interactions/', interactions_list),
    path('api/interactions/create/', create_interaction),
    path('api/interactions/<int:pk>/update/', update_interaction),
    path('api/interactions/<int:pk>/delete/', delete_interaction),
    path('api/employees/dropdown/', employees_for_dropdown),

    # Export
    path('api/export/sales/', export_sales_excel),
    path('api/export/sales/filtered/', export_sales_excel_filtered),
    path('api/export/interactions/', export_interactions_excel),
    path('api/export/interactions/filtered/', export_interactions_excel_filtered),

    # Import
    path('api/import/sales/', import_sales_excel),
    path('api/import/interactions/', import_interactions_excel),

    path('api/reminders/', reminders_list),
    path('api/reminders/create/', create_reminder),
    path('api/reminders/<int:pk>/update/', update_reminder),
    path('api/reminders/<int:pk>/delete/', delete_reminder),

]

# Serve media files in development
if settings.DEBUG:
    urlpatterns += static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)