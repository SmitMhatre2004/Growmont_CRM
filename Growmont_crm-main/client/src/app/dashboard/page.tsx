'use client';

import React, { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { useAuth } from '@/context/AuthContext';
import Sidebar from '@/components/Sidebar';
import Navbar from '@/components/Navbar';
import toast from 'react-hot-toast';
import { SaveIcon, Bell, Calendar, CircleDollarSign, Building2Icon, User2 } from 'lucide-react';
import TodoWidget from '@/components/TodoWidgets';

interface Sale {
  id: number;
  date: string;
  client_name: string;
  sales_rep_name: string;
  product_display: string;
  company: string;
  amount: string;
}

interface Interaction {
  id: number;
  client_name: string;
  client_contact: string;
  follow_up_date: string;
  follow_up_time: string;
  priority: string;
  priority_display: string;
}

interface Reminder {
  id: number;
  event_name: string;
  date: string;
  time: string;
  priority: string;
  type: string;
  employee_name: string;
}

const DashboardPage: React.FC = () => {
  const { token, isLoading } = useAuth();
  const router = useRouter();

  const [currentUser, setCurrentUser] = useState<any>(null);
  const [sales, setSales] = useState<Sale[]>([]);
  const [interactions, setInteractions] = useState<Interaction[]>([]);
  const [reminders, setReminders] = useState<Reminder[]>([]);
  const [stickyNotes, setStickyNotes] = useState<string>('');
  const [loading, setLoading] = useState(true);
  
  // const API_URL = process.env.NEXT_PUBLIC_API_URL || 'http://127.0.0.1:8000';
const API_URL = "";
  // Protect route
  useEffect(() => {
    if (!isLoading && !token) {
      router.push('/');
    }
  }, [isLoading, token, router]);

  // Load sticky notes from localStorage
  useEffect(() => {
    const saved = localStorage.getItem('stickyNotes');
    if (saved) setStickyNotes(saved);
  }, []);

  // Save sticky notes to localStorage
  const saveStickyNotes = (value: string) => {
    setStickyNotes(value);
    localStorage.setItem('stickyNotes', value);
  };

  useEffect(() => {
    if (!token) return;

    const fetchData = async () => {
      try {
        const headers = { 'Authorization': `Bearer ${token}` };

        // Get current user
        const user = JSON.parse(localStorage.getItem('user') || '{}');
        setCurrentUser(user);

        // Fetch Sales (filtered based on role)
        const salesRes = await fetch(`${API_URL}/api/sales/`, { headers });
        const salesData = await salesRes.json();
        if (Array.isArray(salesData)) {
          setSales(salesData.slice(0, 5)); // Only first 5
        }

        // Fetch Interactions (filtered based on role)
        const intRes = await fetch(`${API_URL}/api/interactions/`, { headers });
        const intData = await intRes.json();
        if (Array.isArray(intData)) {
          setInteractions(intData);
        }

        // Fetch Reminders
        const remRes = await fetch(`${API_URL}/api/reminders/`, { headers });
        const remData = await remRes.json();
        if (Array.isArray(remData)) {
          setReminders(remData);
        }

      } catch (error) {
        console.error('Dashboard fetch error:', error);
        toast.error('Failed to load dashboard data');
      } finally {
        setLoading(false);
      }
    };

    fetchData();
  }, [token]);

  const formatAmount = (amount: string) => {
    return new Intl.NumberFormat('en-IN', {
      style: 'currency',
      currency: 'INR',
      maximumFractionDigits: 0,
    }).format(parseFloat(amount));
  };

  // const formatDate = (dateString: string) => {
  //   const date = new Date(dateString);
  //   return date.toLocaleDateString('en-IN', { 
  //     day: '2-digit', 
  //     month: 'short', 
  //     year: 'numeric' 
  //   });
  // };
  const formatDate = (dateString?: string | null) => {
    if (!dateString) return 'No date';

    const date = new Date(dateString);
    return date.toLocaleDateString('en-IN', { 
      day: '2-digit', 
      month: 'short', 
      year: 'numeric' 
    });
  };

  // const formatTime = (timeString: string) => {
  //   const [hours, minutes] = timeString.split(':');
  //   const hour = parseInt(hours);
  //   const ampm = hour >= 12 ? 'PM' : 'AM';
  //   const displayHour = hour % 12 || 12;
  //   return `${displayHour}:${minutes} ${ampm}`;
  // };
  const formatTime = (timeString?: string | null) => {
    if (!timeString) return 'No time';

    const [hours, minutes] = timeString.split(':');
    const hour = parseInt(hours);
    const ampm = hour >= 12 ? 'PM' : 'AM';
    const displayHour = hour % 12 || 12;
    return `${displayHour}:${minutes} ${ampm}`;
  };

  const getPriorityColor = (priority: string) => {
    switch (priority.toUpperCase()) {
      case 'HIGH':
        return 'bg-red-100 text-red-700 border-red-200';
      case 'MEDIUM':
        return 'bg-yellow-100 text-yellow-700 border-yellow-200';
      case 'LOW':
        return 'bg-green-100 text-green-700 border-green-200';
      default:
        return 'bg-gray-100 text-gray-700 border-gray-200';
    }
  };

  if (loading) {
    return (
      <div className="min-h-screen bg-[#F4F9FD]">
        <Sidebar />
        <Navbar />
        {/* Loading: offset for desktop sidebar + mobile topbar */}
        <main className="md:ml-64 mt-16 p-6">
          <div className="text-center py-12">
            <div className="inline-block animate-spin rounded-full h-10 w-10 border-b-2 border-[#2D8A4E]"></div>
            <p className="mt-4 text-gray-600">Loading dashboard...</p>
          </div>
        </main>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-[#F4F9FD]">
      <Sidebar />
      <Navbar />

      {/*
        Desktop: offset left by sidebar width (ml-64) + Navbar height (mt-16)
        Mobile:  no left offset; offset top by mobile topbar height (mt-14) + small gap
      */}
      <main className="md:ml-64 mt-14 md:mt-16 p-4 md:p-6">
        <div className="mb-6">
          <p className="text-gray-600 text-sm mb-1">Welcome back, {currentUser?.name || 'User'}!</p>
          <h1 className="text-2xl md:text-3xl font-bold text-[#00337C]">Dashboard</h1>
        </div>

        {/*
          Desktop: 3-column grid (2 + 1)
          Mobile:  single column stack
        */}
        <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
          {/* LEFT COLUMN - Interactions Follow-up & Recent Sales */}
          <div className="md:col-span-2 space-y-6">
            
            {/* Interaction Follow-ups */}
            <div className="bg-white rounded-2xl border border-gray-200 p-4 md:p-6">
              <h2 className="text-lg md:text-xl font-semibold text-gray-900 mb-4">
                <div className='flex gap-2 items-center'>
                  <Calendar width={20} height={20} color='#00337C' />
                  Upcoming Follow-ups
                </div>
              </h2>
              
              {interactions.length === 0 ? (
                <p className="text-gray-500 text-center py-8">No upcoming follow-ups</p>
              ) : (
                <div className="space-y-3">
                  {interactions.slice(0, 5).map((interaction) => (
                    <div
                      key={interaction.id}
                      className="bg-gray-50 rounded-lg p-3 md:p-4 border border-gray-200 hover:shadow-md transition-shadow"
                    >
                      <div className="flex items-center justify-between gap-2 flex-wrap">
                        <div className="flex-1 min-w-0">
                          <h3 className="font-semibold text-gray-900 truncate">{interaction.client_name}</h3>
                          <p className="text-sm text-gray-600 truncate">{interaction.client_contact}</p>
                        </div>
                        <div className="text-right shrink-0">
                          <p className="text-sm font-medium text-gray-900">
                            {formatDate(interaction.follow_up_date)}
                          </p>
                          <p className="text-sm text-gray-600">
                            {interaction.follow_up_time ? formatTime(interaction.follow_up_time) : 'No time'}
                          </p>                        
                        </div>
                        <span className={`px-3 py-1 rounded-full text-xs font-semibold border ${getPriorityColor(interaction.priority)}`}>
                          {interaction.priority_display}
                        </span>
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </div>

            {/* Recent Sales */}
            <div className="bg-white rounded-2xl border border-gray-200 p-4 md:p-6">
              <div className="flex items-center justify-between mb-4">
                <div className='flex gap-2 items-center'>
                  <CircleDollarSign color='#00337C' />
                  <h2 className="text-lg md:text-xl font-semibold text-gray-900">Recent Sales</h2>
                </div>
                <span className="text-sm text-gray-500">Last 5 entries</span>
              </div>

              {sales.length === 0 ? (
                <p className="text-gray-500 text-center py-8">No sales yet</p>
              ) : (
                <div className="space-y-3">
                  {sales.map((sale) => (
                    <div
                      key={sale.id}
                      className="bg-gray-50 rounded-lg p-3 md:p-4 border border-gray-200 hover:shadow-md transition-shadow"
                    >
                      <div className="flex items-center justify-between gap-2 flex-wrap">
                        <div className="flex-1 min-w-0">
                          <h3 className="font-semibold text-gray-900 truncate">{sale.client_name}</h3>
                          <p className="text-sm text-gray-600 truncate">{sale.company} • {sale.product_display}</p>
                        </div>
                        <div className="text-right shrink-0">
                          <p className="text-base md:text-lg font-bold text-green-600">{formatAmount(sale.amount)}</p>
                          <p className="text-sm text-gray-600">{formatDate(sale.date)}</p>
                        </div>
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </div>
          </div>

          {/* RIGHT COLUMN - Reminders & Sticky Notes */}
          <div className="space-y-6">
            
            {/* Regular Reminders */}
            <div
              className="bg-white rounded-2xl border border-gray-200 p-4 md:p-6 md:sticky md:top-6 cursor-pointer hover:shadow-lg transition-all duration-200 group"
              onClick={() => router.push('/profile?tab=reminders')}
            >
              <div className='flex gap-2 mb-4 items-center group-hover:text-[#2D8A4E] transition-colors'>
                <Bell color='#00337C' />
                <h2 className="text-lg md:text-xl font-semibold text-gray-900">
                  Reminders
                </h2>
              </div>

              {reminders.length === 0 ? (
                <div className="text-center py-8">
                  <svg className="mx-auto h-12 w-12 text-gray-400 group-hover:text-gray-500 transition-colors" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 17h5l-1.405-1.405A2.032 2.032 0 0118 14.158V11a6.002 6.002 0 00-4-5.659V5a2 2 0 10-4 0v.341C7.67 6.165 6 8.388 6 11v3.159c0 .538-.214 1.055-.595 1.436L4 17h5m6 0v1a3 3 0 11-6 0v-1m6 0H9" />
                  </svg>
                  <p className="mt-2 text-gray-500 text-sm">No reminders</p>
                  <p className="text-xs text-gray-400 mt-1 group-hover:text-[#2D8A4E] transition-colors">
                    Click to manage reminders →
                  </p>
                </div>
              ) : (
                <div className="space-y-3 max-h-96 overflow-y-auto">
                  {reminders.map((reminder) => (
                    <div
                      key={reminder.id}
                      className={`rounded-lg p-3 border ${getPriorityColor(reminder.priority)}`}
                    >
                      <div className="flex items-start justify-between gap-2">
                        <div className="flex-1 min-w-0">
                          <h4 className="font-semibold text-sm truncate">{reminder.event_name}</h4>
                          <p className="text-xs text-gray-600 mt-1">
                            {formatDate(reminder.date)} at {formatTime(reminder.time)}
                          </p>
                          {currentUser?.role === 'ADMIN' && reminder.employee_name && (
                            <p className="text-xs text-gray-500 mt-1">👤 {reminder.employee_name}</p>
                          )}
                        </div>
                        <span className="text-xs font-medium shrink-0">
                          {reminder.type === 'CORPORATE' ? <Building2Icon width={18} /> : <User2 width={18} />}
                        </span>
                      </div>
                    </div>
                  ))}
                  {reminders.length > 0 && (
                    <div className="pt-2 mt-3 border-t border-gray-100">
                      <p className="text-xs text-gray-500 hover:text-[#2D8A4E] transition-colors">
                        {reminders.length} reminder{reminders.length !== 1 ? 's' : ''} • Click to manage →
                      </p>
                    </div>
                  )}
                </div>
              )}
            </div>

            {/* Sticky Notes / Todo Widget */}
            <div className="bg-yellow-50 rounded-2xl border-2 border-yellow-200 p-4 md:p-6 md:sticky md:top-[28rem]">
              <TodoWidget userId={currentUser?.id || 0} />
            </div>
          </div>
        </div>
      </main>
    </div>
  );
};

export default DashboardPage;