'use client';

import React, { useState, useEffect } from 'react';
import { useParams, useRouter } from 'next/navigation';
import Sidebar from '@/components/Sidebar';
import Navbar from '@/components/Navbar';
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

interface Sale {
  id: number;
  date: string;
  client_name: string;
  product: string;
  product_display: string;
  company: string;
  scheme: string;
  amount: string;
  frequency_display: string;
}

interface Interaction {
  id: number;
  date: string;
  client_name: string;
  client_contact: string;
  employee: number;
  employee_name: string;
  follow_up_date: string;
  follow_up_time: string;
  priority: string;
  priority_display: string;
  discussion_notes: string;
}

const EmployeeDetailPage: React.FC = () => {
  const params = useParams();
  const router = useRouter();
  const employeeId = params.id as string;

  const [activeTab, setActiveTab] = useState<'sales' | 'interactions'>('sales');
  const [employee, setEmployee] = useState<Employee | null>(null);
  const [interactions, setInteractions] = useState<Interaction[]>([]);
  const [sales, setSales] = useState<Sale[]>([]);
  const [loading, setLoading] = useState(true);
  const [showInfo, setShowInfo] = useState(false);

  // const API_URL = process.env.NEXT_PUBLIC_API_URL || 'http://127.0.0.1:8000';
const API_URL = "";
  useEffect(() => {
    const fetchData = async () => {
      try {
        const token = localStorage.getItem('accessToken');
        if (!token) {
          toast.error('Please login first');
          router.push('/');
          return;
        }
        if (!employeeId) return;

        const headers = {
          'Authorization': `Bearer ${token}`,
          'Content-Type': 'application/json',
        };

        const empRes = await fetch(`${API_URL}/api/employees/${employeeId}/`, { headers });
        if (empRes.status === 401) { toast.error('Session expired'); router.push('/'); return; }
        if (empRes.ok) setEmployee(await empRes.json());

        const interactionsRes = await fetch(`${API_URL}/api/employees/${employeeId}/interactions/`, { headers });
        if (interactionsRes.ok) setInteractions(await interactionsRes.json());

        const salesRes = await fetch(`${API_URL}/api/employees/${employeeId}/sales/`, { headers });
        if (salesRes.ok) setSales(await salesRes.json());

      } catch (err) {
        toast.error('Failed to load employee data');
      } finally {
        setLoading(false);
      }
    };

    fetchData();
  }, [employeeId, router]);

  if (loading) {
    return (
      <div className="min-h-screen bg-[#F4F9FD]">
        <Sidebar />
        <Navbar />
        <main className="md:ml-64 mt-[7.5rem] md:mt-16 p-4 md:p-6">
          <div className="text-center py-12">
            <div className="inline-block animate-spin rounded-full h-10 w-10 border-b-2 border-[#2D8A4E]"></div>
            <p className="mt-4 text-gray-600">Loading employee details...</p>
          </div>
        </main>
      </div>
    );
  }

  if (!employee) {
    return (
      <div className="min-h-screen bg-[#F4F9FD]">
        <Sidebar />
        <Navbar />
        <main className="md:ml-64 mt-[7.5rem] md:mt-16 p-4 md:p-6">
          <div className="text-center py-12 bg-white rounded-2xl">
            <svg className="mx-auto h-12 w-12 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
            </svg>
            <p className="mt-4 text-gray-500">Employee not found</p>
            <button onClick={() => router.push('/employees')} className="mt-4 text-[#2D8A4E] hover:underline font-medium">
              Back to employees
            </button>
          </div>
        </main>
      </div>
    );
  }

  const getGenderDisplay = (gender: string) => {
    switch (gender) {
      case 'M': return 'Male';
      case 'F': return 'Female';
      case 'O': return 'Other';
      default: return gender;
    }
  };

  const formatAmount = (amount: string) => {
    return new Intl.NumberFormat('en-IN', {
      style: 'currency',
      currency: 'INR',
      maximumFractionDigits: 0,
    }).format(parseFloat(amount));
  };

  const EmployeeInfoPanel = () => (
    <div className="bg-white rounded-lg border border-gray-200 p-6">
      {/* Profile */}
      <div className="text-center mb-6">
        <div className="w-24 h-24 rounded-full bg-gradient-to-br from-blue-400 to-purple-500 flex items-center justify-center text-white text-2xl font-semibold ring-4 ring-blue-100 mx-auto">
          {employee.name.split(' ').map(n => n[0]).join('').toUpperCase()}
        </div>
        <h2 className="text-xl font-bold text-gray-900 mt-4">{employee.name}</h2>
        <p className="text-gray-600">{employee.role}</p>
        <span className={`inline-flex mt-2 px-3 py-1 rounded-full text-xs font-semibold ${
          employee.role === 'ADMIN' ? 'bg-purple-100 text-purple-700' : 'bg-blue-100 text-blue-700'
        }`}>
          {employee.role}
        </span>
      </div>

      {/* Main Info */}
      <div className="mb-6">
        <h3 className="font-semibold text-gray-900 mb-4">Main Info</h3>
        <div className="space-y-4">
          <div>
            <label className="text-sm text-gray-600 mb-1 block">Gender</label>
            <input type="text" value={getGenderDisplay(employee.gender)} readOnly
              className="w-full px-4 py-2 bg-gray-50 border border-gray-200 rounded-lg text-gray-900" />
          </div>
          <div>
            <label className="text-sm text-gray-600 mb-1 block">Date of Birth</label>
            <div className="relative">
              <input type="text" value={employee.dob} readOnly
                className="w-full px-4 py-2 bg-gray-50 border border-gray-200 rounded-lg text-gray-900" />
              <svg className="absolute right-3 top-1/2 -translate-y-1/2 w-5 h-5 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z" />
              </svg>
            </div>
          </div>
        </div>
      </div>

      {/* Contact Info */}
      <div>
        <h3 className="font-semibold text-gray-900 mb-4">Contact Info</h3>
        <div className="space-y-4">
          <div>
            <label className="text-sm text-gray-600 mb-1 block">Email</label>
            <input type="email" value={employee.email} readOnly
              className="w-full px-4 py-2 bg-gray-50 border border-gray-200 rounded-lg text-gray-900" />
          </div>
          <div>
            <label className="text-sm text-gray-600 mb-1 block">Mobile Number</label>
            <input type="text" value={employee.mobile_no} readOnly
              className="w-full px-4 py-2 bg-gray-50 border border-gray-200 rounded-lg text-gray-900" />
          </div>
        </div>
      </div>
    </div>
  );

  return (
    <div className="min-h-screen bg-[#F4F9FD]">
      <Sidebar />
      <Navbar />

      <main className="md:ml-64 mt-[4rem] md:mt-16 p-4 md:p-6">
        {/* Header */}
        <div className="flex items-center justify-between mb-6 gap-3">
          <div className="flex items-center gap-3">
            <button
              onClick={() => router.push('/employees')}
              className="p-2 text-gray-600 hover:bg-gray-100 rounded-lg transition-colors"
            >
              <svg className="w-5 h-5 md:w-6 md:h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 19l-7-7 7-7" />
              </svg>
            </button>
            <h1 className="text-xl md:text-3xl font-bold text-[#1e3a8a]">Employee Details</h1>
          </div>

          {/* Mobile: toggle info button */}
          <button
            onClick={() => setShowInfo(prev => !prev)}
            className="md:hidden flex items-center gap-2 border border-gray-300 bg-white text-gray-700 px-3 py-2 rounded-lg font-medium text-sm"
          >
            <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M16 7a4 4 0 11-8 0 4 4 0 018 0zM12 14a7 7 0 00-7 7h14a7 7 0 00-7-7z" />
            </svg>
            {showInfo ? 'Hide Info' : 'View Info'}
          </button>
        </div>

        {/* Mobile: collapsible info panel */}
        {showInfo && (
          <div className="md:hidden mb-4">
            <EmployeeInfoPanel />
          </div>
        )}

        <div className="flex gap-6">
          {/* Left Sidebar - desktop only */}
          <div className="hidden md:block w-96 shrink-0">
            <EmployeeInfoPanel />
          </div>

          {/* Right Content Area */}
          <div className="flex-1 min-w-0">
            {/* Tabs */}
            <div className="flex items-center gap-2 mb-6">
              <button
                onClick={() => setActiveTab('sales')}
                className={`px-4 md:px-6 py-2 rounded-lg font-medium transition-colors text-sm md:text-base ${
                  activeTab === 'sales'
                    ? 'bg-[#2D8A4E] text-white'
                    : 'bg-gray-100 text-gray-600 hover:bg-gray-200'
                }`}
              >
                Sales ({sales.length})
              </button>
              <button
                onClick={() => setActiveTab('interactions')}
                className={`px-4 md:px-6 py-2 rounded-lg font-medium transition-colors text-sm md:text-base ${
                  activeTab === 'interactions'
                    ? 'bg-[#2D8A4E] text-white'
                    : 'bg-gray-100 text-gray-600 hover:bg-gray-200'
                }`}
              >
                Interactions ({interactions.length})
              </button>
            </div>

            {/* Sales Tab */}
            {activeTab === 'sales' && (
              <div className="space-y-4">
                {sales.length === 0 ? (
                  <div className="text-center py-12 bg-white rounded-lg">
                    <svg className="mx-auto h-12 w-12 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 8c-1.657 0-3 .895-3 2s1.343 2 3 2 3 .895 3 2-1.343 2-3 2m0-8c1.11 0 2.08.402 2.599 1M12 8V7m0 1v8m0 0v1m0-1c-1.11 0-2.08-.402-2.599-1M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
                    </svg>
                    <p className="mt-4 text-gray-500">No sales yet</p>
                  </div>
                ) : (
                  sales.map((sale) => (
                    <div key={sale.id} className="bg-white border border-gray-200 rounded-lg p-4 hover:shadow-md transition-shadow">
                      {/* Mobile layout */}
                      <div className="flex md:hidden items-start gap-3">
                        <div className="w-10 h-10 bg-gradient-to-br from-green-400 to-blue-500 rounded-lg flex items-center justify-center text-white font-bold shrink-0">
                          ₹
                        </div>
                        <div className="flex-1 min-w-0">
                          <h3 className="font-semibold text-gray-900 truncate">{sale.client_name}</h3>
                          <p className="text-xs text-gray-500 mt-0.5">{sale.date}</p>
                          <div className="grid grid-cols-2 gap-x-4 gap-y-1 mt-2">
                            <div>
                              <p className="text-xs text-gray-500">Product</p>
                              <p className="text-sm font-semibold text-gray-900">{sale.product_display}</p>
                            </div>
                            <div>
                              <p className="text-xs text-gray-500">Company</p>
                              <p className="text-sm font-semibold text-gray-900 truncate">{sale.company}</p>
                            </div>
                            <div>
                              <p className="text-xs text-gray-500">Amount</p>
                              <p className="text-sm font-semibold text-green-600">{formatAmount(sale.amount)}</p>
                            </div>
                            <div>
                              <p className="text-xs text-gray-500">Frequency</p>
                              <p className="text-sm font-semibold text-gray-900">{sale.frequency_display}</p>
                            </div>
                          </div>
                        </div>
                      </div>

                      {/* Desktop layout */}
                      <div className="hidden md:flex items-center justify-between">
                        <div className="flex items-center gap-4 flex-1">
                          <div className="w-10 h-10 bg-gradient-to-br from-green-400 to-blue-500 rounded-lg flex items-center justify-center text-white font-bold">
                            ₹
                          </div>
                          <div>
                            <h3 className="font-semibold text-gray-900">{sale.client_name}</h3>
                            <div className="flex items-center gap-2 text-xs text-gray-600 mt-1">
                              <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z" />
                              </svg>
                              <span>{sale.date}</span>
                            </div>
                          </div>
                        </div>
                        <div className="bg-gray-50 px-6 py-3 rounded-lg">
                          <div className="grid grid-cols-4 gap-6 text-center">
                            <div>
                              <p className="text-xs text-gray-500 mb-1">Product</p>
                              <p className="font-semibold text-gray-900 text-sm">{sale.product_display}</p>
                            </div>
                            <div>
                              <p className="text-xs text-gray-500 mb-1">Company</p>
                              <p className="font-semibold text-gray-900 text-sm">{sale.company}</p>
                            </div>
                            <div>
                              <p className="text-xs text-gray-500 mb-1">Amount</p>
                              <p className="font-semibold text-green-600 text-sm">{formatAmount(sale.amount)}</p>
                            </div>
                            <div>
                              <p className="text-xs text-gray-500 mb-1">Frequency</p>
                              <p className="font-semibold text-gray-900 text-sm">{sale.frequency_display}</p>
                            </div>
                          </div>
                        </div>
                      </div>
                    </div>
                  ))
                )}
              </div>
            )}

            {/* Interactions Tab */}
            {activeTab === 'interactions' && (
              <div className="grid grid-cols-2 md:grid-cols-4 gap-4 md:gap-6">
                {interactions.length === 0 ? (
                  <div className="col-span-2 md:col-span-4 text-center py-12 bg-white rounded-lg">
                    <svg className="mx-auto h-12 w-12 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0zm6 3a2 2 0 11-4 0 2 2 0 014 0zM7 10a2 2 0 11-4 0 2 2 0 014 0z" />
                    </svg>
                    <p className="mt-4 text-gray-500">No interactions yet</p>
                  </div>
                ) : (
                  interactions.map((interaction) => (
                    <div key={interaction.id} className="bg-white rounded-lg border border-gray-200 p-4 md:p-6 hover:shadow-md transition-shadow">
                      <div className="flex flex-col items-center text-center">
                        <div className="w-14 h-14 md:w-20 md:h-20 rounded-full bg-gradient-to-br from-blue-400 to-purple-500 flex items-center justify-center text-white text-base md:text-xl font-semibold mb-3 ring-4 ring-blue-100">
                          {interaction.client_name.split(' ').map(n => n[0]).join('').toUpperCase()}
                        </div>
                        <h3 className="font-semibold text-gray-900 mb-1 text-sm md:text-base">{interaction.follow_up_date}</h3>
                        <p className="text-xs md:text-sm text-gray-600">{interaction.client_contact}</p>
                      </div>
                    </div>
                  ))
                )}
              </div>
            )}
          </div>
        </div>
      </main>
    </div>
  );
};

export default EmployeeDetailPage;