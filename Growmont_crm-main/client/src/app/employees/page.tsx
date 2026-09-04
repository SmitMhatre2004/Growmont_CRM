
'use client';

import React, { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { useAuth } from '@/context/AuthContext';
import Sidebar from '@/components/Sidebar';
import Navbar from '@/components/Navbar';
import AddEmployeeModal from '@/components/AddEmployeeModal';
import toast from 'react-hot-toast';

interface Employee {
  id: number;
  name: string;
  email: string;
  mobile_no: string;
  gender: string;
  dob: string;
  role: string;
  avatar: string | null;
  clients_count: number;
  sales_count: number;
  interactions_count: number;
}

const EmployeesPage: React.FC = () => {
  const { token } = useAuth();
  const router = useRouter();
  const [openEmployee, setOpenEmployee] = useState(false);
  const [employees, setEmployees] = useState<Employee[]>([]);
  const [loading, setLoading] = useState(true);
  const [currentUserRole, setCurrentUserRole] = useState<string>('');
  const [editingEmployee, setEditingEmployee] = useState<Employee | null>(null);
  
  // const API_URL = process.env.NEXT_PUBLIC_API_URL || 'http://127.0.0.1:8000';
const API_URL = "";

  useEffect(() => {
    if (!token) {
      router.push('/');
      return;
    }
    const user = JSON.parse(localStorage.getItem('user') || '{}');
    setCurrentUserRole(user.role || '');
    fetchEmployees();
  }, [token]);

  const fetchEmployees = async () => {
    try {
      setLoading(true);
      const response = await fetch(`${API_URL}/api/employees/`, {
        headers: { 
          'Authorization': `Bearer ${token}`,
          'Content-Type': 'application/json',
        }
      });

      if (response.status === 401) {
        toast.error('Session expired. Please login again.');
        router.push('/');
        return;
      }

      if (!response.ok) throw new Error('Failed to fetch employees');

      const data = await response.json();
      if (Array.isArray(data)) {
        setEmployees(data);
      } else {
        setEmployees([]);
        toast.error('Invalid data format received');
      }
    } catch (err) {
      toast.error('Failed to load employees');
      setEmployees([]);
    } finally {
      setLoading(false);
    }
  };

  const handleEdit = (employee: Employee) => {
    setEditingEmployee(employee);
    setOpenEmployee(true);
  };

  const handleDelete = async (id: number, name: string) => {
    if (!confirm(`Are you sure you want to delete ${name}? This action cannot be undone.`)) return;

    try {
      const response = await fetch(`${API_URL}/api/employees/${id}/delete/`, {
        method: 'DELETE',
        headers: {
          'Authorization': `Bearer ${token}`,
          'Content-Type': 'application/json',
        }
      });

      if (response.ok) {
        toast.success('Employee deleted successfully');
        fetchEmployees();
      } else {
        const errorData = await response.json();
        toast.error(errorData.error || 'Failed to delete employee');
      }
    } catch (err) {
      toast.error('Failed to delete employee');
    }
  };

  const handleEmployeeAdded = () => {
    toast.success(editingEmployee ? 'Employee updated successfully!' : 'Employee added successfully!');
    setEditingEmployee(null);
    fetchEmployees();
  };

  const handleCloseModal = () => {
    setOpenEmployee(false);
    setEditingEmployee(null);
  };

  const getGenderDisplay = (gender: string) => {
    switch (gender) {
      case 'M': return 'Male';
      case 'F': return 'Female';
      case 'O': return 'Other';
      default: return gender;
    }
  };

  return (
    <div className="min-h-screen bg-[#F4F9FD]">
      <Sidebar />
      <Navbar />

      <main className="md:ml-64 mt-[4rem] md:mt-16 p-4 md:p-6">
        <div className="flex items-center justify-between mb-6 gap-3">
          <div>
            <h1 className="text-2xl md:text-3xl font-bold text-gray-900">Employees</h1>
            <p className="text-sm text-gray-500 mt-1">Manage your team members</p>
          </div>

          {currentUserRole === 'ADMIN' && (
            <button
              className="flex items-center gap-2 bg-[#2D8A4E] text-white px-3 md:px-4 py-2 rounded-lg hover:bg-[#236b3d] transition-colors text-sm md:text-base"
              onClick={() => {
                setEditingEmployee(null);
                setOpenEmployee(true);
              }}
            >
              <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 4v16m8-8H4" />
              </svg>
              Add Employee
            </button>
          )}
        </div>

        <AddEmployeeModal
          isOpen={openEmployee}
          onClose={handleCloseModal}
          onSuccess={handleEmployeeAdded}
          initialData={editingEmployee}
        />

        {loading ? (
          <div className="text-center py-12">
            <div className="inline-block animate-spin rounded-full h-10 w-10 border-b-2 border-[#2D8A4E]"></div>
            <p className="mt-4 text-gray-600">Loading employees...</p>
          </div>
        ) : employees.length === 0 ? (
          <div className="text-center py-12 bg-white rounded-2xl">
            <svg className="mx-auto h-12 w-12 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0zm6 3a2 2 0 11-4 0 2 2 0 014 0zM7 10a2 2 0 11-4 0 2 2 0 014 0z" />
            </svg>
            <p className="mt-4 text-gray-500">No employees found</p>
            {currentUserRole === 'ADMIN' && (
              <button
                onClick={() => setOpenEmployee(true)}
                className="mt-4 text-[#2D8A4E] hover:underline font-medium"
              >
                Add your first employee
              </button>
            )}
          </div>
        ) : (
          <div className="space-y-3">
            {employees.map(emp => (
              <div
                key={emp.id}
                className="bg-white p-4 md:p-6 rounded-2xl hover:shadow-md transition-shadow border border-gray-100"
              >
                {/* ── MOBILE LAYOUT ── */}
                <div className="flex md:hidden items-start gap-3">
                  {/* Avatar */}
                  <div
                    className="w-12 h-12 rounded-full bg-gradient-to-br from-blue-400 to-purple-500 flex items-center justify-center text-white font-semibold flex-shrink-0 cursor-pointer"
                    onClick={() => router.push(`/employees/${emp.id}`)}
                  >
                    {emp.name.split(' ').map(n => n[0]).join('').toUpperCase()}
                  </div>

                  {/* Info */}
                  <div
                    className="flex-1 min-w-0 cursor-pointer"
                    onClick={() => router.push(`/employees/${emp.id}`)}
                  >
                    <h3 className="font-semibold text-gray-900 truncate">{emp.name}</h3>
                    <p className="text-xs text-gray-500 truncate">{emp.email}</p>
                    <p className="text-xs text-gray-500">{emp.mobile_no}</p>
                    <div className="flex items-center gap-2 mt-1 flex-wrap">
                      <span className={`inline-flex px-2 py-0.5 rounded-full text-xs font-semibold ${
                        emp.role === 'ADMIN' ? 'bg-purple-100 text-purple-700' : 'bg-blue-100 text-blue-700'
                      }`}>
                        {emp.role}
                      </span>
                      <span className="text-xs text-gray-500">{getGenderDisplay(emp.gender)}</span>
                      <span className="text-xs text-blue-600 font-semibold">{emp.sales_count || 0} sales</span>
                      <span className="text-xs text-purple-600 font-semibold">{emp.interactions_count || 0} interactions</span>
                    </div>
                  </div>

                  {/* Actions */}
                  {currentUserRole === 'ADMIN' && (
                    <div className="flex flex-col gap-1 shrink-0">
                      <button
                        onClick={(e) => { e.stopPropagation(); handleEdit(emp); }}
                        className="p-2 text-blue-600 hover:bg-blue-50 rounded-lg transition-colors"
                        title="Edit Employee"
                      >
                        <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z" />
                        </svg>
                      </button>
                      <button
                        onClick={(e) => { e.stopPropagation(); handleDelete(emp.id, emp.name); }}
                        className="p-2 text-red-600 hover:bg-red-50 rounded-lg transition-colors"
                        title="Delete Employee"
                      >
                        <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
                        </svg>
                      </button>
                    </div>
                  )}
                </div>

                {/* ── DESKTOP LAYOUT ── */}
                <div className="hidden md:flex items-center gap-6">
                  {/* Avatar & Name */}
                  <div
                    className="flex items-center gap-4 flex-1 min-w-0 cursor-pointer"
                    onClick={() => router.push(`/employees/${emp.id}`)}
                  >
                    <div className="w-14 h-14 rounded-full bg-gradient-to-br from-blue-400 to-purple-500 flex items-center justify-center text-white font-semibold flex-shrink-0">
                      {emp.name.split(' ').map(n => n[0]).join('').toUpperCase()}
                    </div>
                    <div className="min-w-0">
                      <h3 className="font-semibold text-gray-900 truncate">{emp.name}</h3>
                      <p className="text-sm text-gray-500 truncate">{emp.email}</p>
                    </div>
                  </div>

                  {/* Role */}
                  <div className="w-32">
                    <p className="text-xs text-gray-500">Role</p>
                    <span className={`inline-flex px-2 py-1 rounded-full text-xs font-semibold ${
                      emp.role === 'ADMIN' ? 'bg-purple-100 text-purple-700' : 'bg-blue-100 text-blue-700'
                    }`}>
                      {emp.role}
                    </span>
                  </div>

                  {/* Gender */}
                  <div className="w-24">
                    <p className="text-xs text-gray-500">Gender</p>
                    <p className="font-medium">{getGenderDisplay(emp.gender)}</p>
                  </div>

                  {/* Mobile */}
                  <div className="w-32">
                    <p className="text-xs text-gray-500">Mobile</p>
                    <p className="font-medium">{emp.mobile_no}</p>
                  </div>

                  {/* Stats */}
                  <div className="w-20">
                    <p className="text-xs text-gray-500">Sales</p>
                    <p className="font-bold text-blue-600">{emp.sales_count || 0}</p>
                  </div>

                  <div className="w-24">
                    <p className="text-xs text-gray-500">Interactions</p>
                    <p className="font-bold text-purple-600">{emp.interactions_count || 0}</p>
                  </div>

                  {/* Action Buttons */}
                  {currentUserRole === 'ADMIN' && (
                    <div className="flex items-center gap-2">
                      <button
                        onClick={(e) => { e.stopPropagation(); handleEdit(emp); }}
                        className="p-2 text-blue-600 hover:bg-blue-50 rounded-lg transition-colors"
                        title="Edit Employee"
                      >
                        <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z" />
                        </svg>
                      </button>
                      <button
                        onClick={(e) => { e.stopPropagation(); handleDelete(emp.id, emp.name); }}
                        className="p-2 text-red-600 hover:bg-red-50 rounded-lg transition-colors"
                        title="Delete Employee"
                      >
                        <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
                        </svg>
                      </button>
                    </div>
                  )}
                </div>

              </div>
            ))}
          </div>
        )}
      </main>
    </div>
  );
};

export default EmployeesPage;