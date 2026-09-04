"use client";
import React, { useState, useEffect } from "react";
import Sidebar from "@/components/Sidebar";
import Navbar from "@/components/Navbar";
import AddReminderModal from "@/components/AddReminderModal";

import { useAuth } from "@/context/AuthContext";
import { useRouter } from "next/navigation";

interface User {
  id: string;
  name: string;
  birthday: string;
  email: string;
  mobile: string;
  avatar: string;
  gender: string;
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

interface ProductSale {
  id: string;
  productId: string;
  clientName: string;
  createdDate: string;
  priority: string;
  category: string;
  amount: number;
  categoryCount: number;
  representatives: string[];
}

interface Reminder {
  id: number;
  employee: number;
  employee_name: string;
  event_name: string;
  type: string;
  priority: string;
  date: string;
  time: string;
  end_time: string;
  description: string;
  repeat_reminder: boolean;
  repeat_type: string;
  repeat_days: string[];
  repeat_every_day: boolean;
}

type TabType = "interactions" | "productSales" | "reminders";

const ProfilePage = () => {
  const { user: authUser, isLoading } = useAuth();
  const router = useRouter();

  const [activeTab, setActiveTab] = useState<TabType>("reminders");
  const [openReminder, setOpenReminder] = useState(false);
  const [editingReminder, setEditingReminder] = useState<Reminder | null>(null);
  const [deletingReminder, setDeletingReminder] = useState<number | null>(null);
  const [showProfilePanel, setShowProfilePanel] = useState(false);

  const [user, setUser] = useState<User | null>(null);
  const [interactions, setInteractions] = useState<Interaction[]>([]);
  const [productSales, setProductSales] = useState<ProductSale[]>([]);
  const [reminders, setReminders] = useState<Reminder[]>([]);
  const [loading, setLoading] = useState(true);

  // const API_URL = process.env.NEXT_PUBLIC_API_URL || 'http://127.0.0.1:8000';
const API_URL = "";

  useEffect(() => {
    if (!isLoading && !authUser) {
      router.push('/');
    }
  }, [isLoading, authUser, router]);

  const fetchProfileData = async () => {
    if (!authUser) return;
    try {
      const userId = authUser.id;
      const token = localStorage.getItem('accessToken');
      const headers = { 'Authorization': `Bearer ${token}`, 'Content-Type': 'application/json' };

      const userRes = await fetch(`${API_URL}/api/employees/${userId}/`, { headers });
      if (userRes.ok) {
        const userData = await userRes.json();
        setUser({ id: String(userData.id), name: userData.name, birthday: userData.dob, email: userData.email, mobile: userData.mobile_no, avatar: userData.avatar || "", gender: userData.gender });
      }

      const interactionsRes = await fetch(`${API_URL}/api/interactions/`, { headers });
      if (interactionsRes.ok) setInteractions(await interactionsRes.json());

      const salesRes = await fetch(`${API_URL}/api/employees/${userId}/sales/`, { headers });
      if (salesRes.ok) {
        const salesData = await salesRes.json();
        setProductSales(salesData.map((s: any) => ({
          id: String(s.id), productId: s.product_display || s.product, clientName: s.client_name || "Unknown",
          createdDate: s.date, priority: "High", category: s.product_display || "Unknown",
          amount: parseFloat(s.amount), categoryCount: 1, representatives: ["/avatar.png"]
        })));
      }

      const remindersRes = await fetch(`${API_URL}/api/reminders/`, { headers });
      if (remindersRes.ok) setReminders(await remindersRes.json());

    } catch (err) {
      console.error("Profile fetch error:", err);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => { fetchProfileData(); }, [authUser]);

  const getPriorityColor = (priority: string) => {
    const p = priority.toLowerCase();
    if (p.includes("high")) return "text-red-500";
    if (p.includes("medium")) return "text-yellow-500";
    if (p.includes("low")) return "text-green-500";
    return "text-gray-500";
  };

  const getPriorityBadgeColor = (priority: string) => {
    const p = priority.toLowerCase();
    if (p.includes("high")) return "bg-red-100 text-red-700 border-red-200";
    if (p.includes("medium")) return "bg-yellow-100 text-yellow-700 border-yellow-200";
    if (p.includes("low")) return "bg-green-100 text-green-700 border-green-200";
    return "bg-gray-100 text-gray-700 border-gray-200";
  };

  const getReminderIconBg = (type: string) => type === "CORPORATE" ? "bg-blue-100 text-blue-600" : "bg-purple-100 text-purple-600";

  const getInitials = (name: string) => name.split(' ').map(n => n[0]).join('').toUpperCase();

  const getGenderDisplay = (gender: string) => {
    switch (gender) {
      case 'M': return 'Male';
      case 'F': return 'Female';
      case 'O': return 'Other';
      default: return 'Not specified';
    }
  };

  const handleReminderAdded = () => { fetchProfileData(); setEditingReminder(null); };
  const handleEditReminder = (reminder: Reminder) => { setEditingReminder(reminder); setOpenReminder(true); };

  const handleDeleteReminder = async (id: number) => {
    if (!confirm("Are you sure you want to delete this reminder?")) return;
    setDeletingReminder(id);
    try {
      const token = localStorage.getItem('accessToken');
      const res = await fetch(`${API_URL}/api/reminders/${id}/delete/`, { method: 'DELETE', headers: { 'Authorization': `Bearer ${token}` } });
      if (!res.ok) throw new Error('Failed to delete reminder');
      await fetchProfileData();
    } catch (err) {
      alert("Failed to delete reminder");
    } finally {
      setDeletingReminder(null);
    }
  };

  const handleCloseModal = () => { setOpenReminder(false); setEditingReminder(null); };

  if (loading) return <div className="p-6">Loading profile...</div>;
  if (!user) return <div className="p-6">User not found</div>;

  const ProfileInfoPanel = () => (
    <div className="bg-white rounded-lg shadow-sm p-6">
      {/* Profile Header */}
      <div className="flex items-start justify-between mb-6">
        <div className="flex items-center gap-3">
          <div className="relative">
            {user.avatar ? (
              <img src={user.avatar} alt={user.name} className="w-16 h-16 rounded-full border-4 border-blue-500" />
            ) : (
              <div className="w-16 h-16 rounded-full bg-gradient-to-br from-blue-400 to-purple-500 flex items-center justify-center text-white font-semibold border-4 border-blue-500 text-lg">
                {getInitials(user.name)}
              </div>
            )}
          </div>
          <div>
            <h2 className="text-lg font-bold text-gray-900">{user.name}</h2>
          </div>
        </div>
      </div>

      {/* Main Info */}
      <div className="mb-6">
        <h3 className="text-sm font-semibold text-gray-900 mb-4">Main info</h3>
        <div className="space-y-4">
          <div>
            <label className="text-xs text-gray-500 mb-1 block">Gender</label>
            <input readOnly type="text" value={getGenderDisplay(user.gender)}
              className="w-full px-3 py-2 border border-gray-200 rounded-lg text-sm text-gray-700 bg-gray-50" />
          </div>
          <div>
            <label className="text-xs text-gray-500 mb-1 block">Birthday Date</label>
            <div className="relative">
              <input readOnly type="text" value={user.birthday}
                className="w-full px-3 py-2 border border-gray-200 rounded-lg text-sm text-gray-700 bg-gray-50" />
              <svg className="w-5 h-5 text-gray-400 absolute right-3 top-2.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z" />
              </svg>
            </div>
          </div>
        </div>
      </div>

      {/* Contact Info */}
      <div>
        <h3 className="text-sm font-semibold text-gray-900 mb-4">Contact Info</h3>
        <div className="space-y-4">
          <div>
            <label className="text-xs text-gray-500 mb-1 block">Email</label>
            <input type="email" value={user.email} readOnly
              className="w-full px-3 py-2 border border-gray-200 rounded-lg text-sm text-gray-700 bg-gray-50" />
          </div>
          <div>
            <label className="text-xs text-gray-500 mb-1 block">Mobile Number</label>
            <input type="text" value={user.mobile} readOnly
              className="w-full px-3 py-2 border border-gray-200 rounded-lg text-sm text-gray-700 bg-gray-50" />
          </div>
        </div>
      </div>
    </div>
  );

  return (
    <div className="min-h-screen bg-[#F4F9FD]">
      <Sidebar />
      <Navbar />

      <div className="md:ml-64 mt-[4rem] md:mt-16 p-4 md:p-6">
        <main className="flex-1 overflow-y-auto">

          {/* Header */}
          <div className="flex justify-between items-center mb-6 gap-3">
            <h1 className="text-2xl md:text-3xl font-bold text-gray-900">Profile</h1>
            <div className="flex items-center gap-2">
              {/* Mobile: toggle profile info */}
              <button
                onClick={() => setShowProfilePanel(prev => !prev)}
                className="md:hidden flex items-center gap-2 border border-gray-300 bg-white text-gray-700 px-3 py-2 rounded-lg font-medium text-sm"
              >
                <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M16 7a4 4 0 11-8 0 4 4 0 018 0zM12 14a7 7 0 00-7 7h14a7 7 0 00-7-7z" />
                </svg>
                {showProfilePanel ? 'Hide Info' : 'My Info'}
              </button>

              <button
                onClick={() => { setEditingReminder(null); setOpenReminder(true); }}
                className="flex items-center gap-2 bg-[#2D8A4E] text-white px-3 md:px-6 py-2 md:py-2.5 rounded-lg hover:bg-[#236b3d] transition-colors shadow-md text-sm md:text-base"
              >
                <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 4v16m8-8H4" />
                </svg>
                <span>Add Reminder</span>
              </button>
            </div>
          </div>

          {/* Mobile: collapsible profile panel */}
          {showProfilePanel && (
            <div className="md:hidden mb-4">
              <ProfileInfoPanel />
            </div>
          )}

          <div className="flex gap-6">
            {/* Left Panel - desktop only */}
            <div className="hidden md:block w-72 shrink-0">
              <ProfileInfoPanel />
            </div>

            {/* Right Panel - Tabs Content */}
            <div className="flex-1 min-w-0">
              <div className="bg-white rounded-lg shadow-sm p-4 md:p-6">
                {/* Tabs - scrollable on mobile */}
                <div className="flex gap-2 mb-6 overflow-x-auto pb-1">
                  <button
                    onClick={() => setActiveTab("productSales")}
                    className={`px-4 md:px-6 py-2 rounded-full text-sm font-medium transition whitespace-nowrap ${activeTab === "productSales" ? "bg-[#2D8A4E] text-white" : "bg-gray-100 text-gray-600 hover:bg-gray-200"}`}
                  >
                    Product Sales
                  </button>
                  <button
                    onClick={() => setActiveTab("interactions")}
                    className={`px-4 md:px-6 py-2 rounded-full text-sm font-medium transition whitespace-nowrap ${activeTab === "interactions" ? "bg-[#2D8A4E] text-white" : "bg-gray-100 text-gray-600 hover:bg-gray-200"}`}
                  >
                    Interactions
                  </button>
                  <button
                    onClick={() => setActiveTab("reminders")}
                    className={`px-4 md:px-6 py-2 rounded-full text-sm font-medium transition whitespace-nowrap ${activeTab === "reminders" ? "bg-[#2D8A4E] text-white" : "bg-gray-100 text-gray-600 hover:bg-gray-200"}`}
                  >
                    Reminders
                  </button>
                </div>

                {/* Interactions Tab */}
                {activeTab === "interactions" && (
                  <div className="space-y-4">
                    {interactions.length === 0 ? (
                      <div className="text-center py-12">
                        <svg className="w-16 h-16 text-gray-300 mx-auto mb-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0zm6 3a2 2 0 11-4 0 2 2 0 014 0zM7 10a2 2 0 11-4 0 2 2 0 014 0z" />
                        </svg>
                        <p className="text-gray-500">No interactions yet</p>
                      </div>
                    ) : (
                      interactions.map((interaction) => (
                        <div key={interaction.id} className="bg-gray-50 rounded-lg p-4 hover:shadow-md transition border-l-4 border-blue-500">
                          <div className="flex items-start justify-between flex-wrap gap-2">
                            <div className="flex-1 min-w-0">
                              <div className="flex items-center gap-2 flex-wrap mb-2">
                                <h3 className="font-semibold text-gray-900 text-base md:text-lg">{interaction.client_name}</h3>
                                <span className={`px-3 py-1 rounded-full text-xs font-medium border ${getPriorityBadgeColor(interaction.priority_display)}`}>
                                  {interaction.priority_display}
                                </span>
                              </div>
                              <div className="space-y-1 text-sm text-gray-600 mb-3">
                                <p className="flex items-center gap-2">
                                  <svg className="w-4 h-4 shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M3 5a2 2 0 012-2h3.28a1 1 0 01.948.684l1.498 4.493a1 1 0 01-.502 1.21l-2.257 1.13a11.042 11.042 0 005.516 5.516l1.13-2.257a1 1 0 011.21-.502l4.493 1.498a1 1 0 01.684.949V19a2 2 0 01-2 2h-1C9.716 21 3 14.284 3 6V5z" />
                                  </svg>
                                  {interaction.client_contact}
                                </p>
                                <p className="flex items-center gap-2">
                                  <svg className="w-4 h-4 shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z" />
                                  </svg>
                                  Interaction Date: {interaction.date}
                                </p>
                                <p className="flex items-center gap-2">
                                  <svg className="w-4 h-4 shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z" />
                                  </svg>
                                  Follow-up: {interaction.follow_up_date} at {interaction.follow_up_time}
                                </p>
                              </div>
                              {interaction.discussion_notes && (
                                <div className="bg-white rounded p-3 text-sm text-gray-700">
                                  <p className="font-medium text-gray-900 mb-1">Notes:</p>
                                  {interaction.discussion_notes}
                                </div>
                              )}
                            </div>
                          </div>
                        </div>
                      ))
                    )}
                  </div>
                )}

                {/* Product Sales Tab */}
                {activeTab === "productSales" && (
                  <div className="space-y-4">
                    {productSales.length === 0 ? (
                      <div className="text-center py-12">
                        <svg className="w-16 h-16 text-gray-300 mx-auto mb-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M16 11V7a4 4 0 00-8 0v4M5 9h14l1 12H4L5 9z" />
                        </svg>
                        <p className="text-gray-500">No sales yet</p>
                      </div>
                    ) : (
                      productSales.map((sale) => (
                        <div key={sale.id} className="flex flex-col md:flex-row md:items-center md:justify-between gap-3 p-4 bg-gray-50 rounded-lg hover:shadow-md transition">
                          {/* Client info */}
                          <div className="flex items-center gap-3 flex-1 min-w-0">
                            <div className="w-10 h-10 bg-gradient-to-br from-yellow-400 to-pink-500 rounded-lg shrink-0"></div>
                            <div className="min-w-0">
                              <p className="text-xs text-gray-500 truncate">{sale.productId}</p>
                              <p className="font-semibold text-gray-900 truncate">{sale.clientName}</p>
                            </div>
                          </div>

                          {/* Date & Priority - row on mobile */}
                          <div className="flex items-center gap-4 text-sm flex-wrap">
                            <div className="flex items-center gap-1 text-gray-500">
                              <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M21 13.255A23.931 23.931 0 0112 15c-3.183 0-6.22-.62-9-1.745M16 6V4a2 2 0 00-2-2h-4a2 2 0 00-2 2v2m4 6h.01M5 20h14a2 2 0 002-2V8a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z" />
                              </svg>
                              Created {sale.createdDate}
                            </div>
                            <p className={`text-sm font-medium flex items-center gap-1 ${getPriorityColor(sale.priority)}`}>
                              ↑ {sale.priority}
                            </p>
                          </div>

                          {/* Sale detail card */}
                          <div className="bg-white border border-gray-200 rounded-lg p-3 w-full md:min-w-[220px] md:w-auto">
                            <h4 className="text-sm font-semibold text-gray-900 mb-2">{sale.category}</h4>
                            <div className="flex items-center justify-between gap-2">
                              <div>
                                <p className="text-xs text-gray-500">Amount</p>
                                <p className="font-semibold text-gray-900 text-sm">{sale.amount}</p>
                              </div>
                              <div>
                                <p className="text-xs text-gray-500">Category</p>
                                <p className="font-semibold text-gray-900 text-sm">{sale.categoryCount}</p>
                              </div>
                              <div>
                                <p className="text-xs text-gray-500 mb-1">Rep</p>
                                <div className="flex -space-x-2">
                                  {sale.representatives.map((rep, idx) => (
                                    <img key={idx} src={rep} alt="" className="w-6 h-6 rounded-full border-2 border-white" />
                                  ))}
                                </div>
                              </div>
                            </div>
                          </div>
                        </div>
                      ))
                    )}
                  </div>
                )}

                {/* Reminders Tab */}
                {activeTab === "reminders" && (
                  <div className="space-y-4">
                    {reminders.length === 0 ? (
                      <div className="text-center py-12">
                        <svg className="w-16 h-16 text-gray-300 mx-auto mb-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z" />
                        </svg>
                        <p className="text-gray-500 mb-2">No reminders yet</p>
                        <button onClick={() => { setEditingReminder(null); setOpenReminder(true); }} className="text-[#2D8A4E] hover:underline font-medium">
                          Add your first reminder
                        </button>
                      </div>
                    ) : (
                      reminders.map((reminder) => (
                        <div key={reminder.id} className="bg-white rounded-lg p-4 hover:shadow-md transition border-l-4 border-green-500">
                          <div className="flex items-start justify-between gap-2">
                            <div className="flex items-start gap-3 flex-1 min-w-0">
                              <div className={`w-10 h-10 md:w-12 md:h-12 rounded-lg flex items-center justify-center shrink-0 ${getReminderIconBg(reminder.type)}`}>
                                <svg className="w-5 h-5 md:w-6 md:h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z" />
                                </svg>
                              </div>
                              <div className="flex-1 min-w-0">
                                <div className="flex items-center gap-2 flex-wrap mb-2">
                                  <h3 className="font-semibold text-gray-900 text-base md:text-lg">{reminder.event_name}</h3>
                                  <span className={`px-3 py-1 rounded-full text-xs font-medium border ${getPriorityBadgeColor(reminder.priority)}`}>
                                    {reminder.priority}
                                  </span>
                                </div>
                                <div className="flex flex-wrap items-center gap-2 md:gap-4 text-sm text-gray-600 mb-2">
                                  <span className="flex items-center gap-1">
                                    <svg className="w-4 h-4 shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z" />
                                    </svg>
                                    {reminder.date}
                                  </span>
                                  <span className="flex items-center gap-1">
                                    <svg className="w-4 h-4 shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z" />
                                    </svg>
                                    {reminder.time}{reminder.end_time && ` - ${reminder.end_time}`}
                                  </span>
                                  <span className="px-2 py-1 bg-gray-100 rounded text-xs">
                                    {reminder.type === "CORPORATE" ? "Corporate Event" : "Personal"}
                                  </span>
                                </div>
                                {reminder.description && (
                                  <p className="text-sm text-gray-700 mb-2">{reminder.description}</p>
                                )}
                                {reminder.repeat_reminder && (
                                  <div className="flex items-center gap-2 text-xs text-gray-500">
                                    <svg className="w-4 h-4 shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
                                    </svg>
                                    Repeats: {reminder.repeat_type}
                                    {reminder.repeat_days.length > 0 && ` (${reminder.repeat_days.join(", ")})`}
                                  </div>
                                )}
                              </div>
                            </div>

                            {/* Action Buttons */}
                            <div className="flex flex-col md:flex-row items-center gap-1 md:gap-2 shrink-0">
                              <button onClick={() => handleEditReminder(reminder)} className="p-2 text-blue-600 hover:bg-blue-50 rounded-lg transition" title="Edit reminder">
                                <svg className="w-4 h-4 md:w-5 md:h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z" />
                                </svg>
                              </button>
                              <button
                                onClick={() => handleDeleteReminder(reminder.id)}
                                disabled={deletingReminder === reminder.id}
                                className="p-2 text-red-600 hover:bg-red-50 rounded-lg transition disabled:opacity-50"
                                title="Delete reminder"
                              >
                                {deletingReminder === reminder.id ? (
                                  <svg className="w-4 h-4 md:w-5 md:h-5 animate-spin" fill="none" viewBox="0 0 24 24">
                                    <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4"></circle>
                                    <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                                  </svg>
                                ) : (
                                  <svg className="w-4 h-4 md:w-5 md:h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
                                  </svg>
                                )}
                              </button>
                            </div>
                          </div>
                        </div>
                      ))
                    )}
                  </div>
                )}
              </div>
            </div>
          </div>

          {/* Change Password Section */}
          <div className="bg-white rounded-lg shadow-sm p-4 md:p-6 mt-6 max-w-2xl">
            <h2 className="text-xl font-bold text-gray-900 mb-6">Change Password</h2>
            <ChangePasswordForm />
          </div>
        </main>
      </div>

      <AddReminderModal
        isOpen={openReminder}
        onClose={handleCloseModal}
        onReminderAdded={handleReminderAdded}
        editingReminder={editingReminder}
      />
    </div>
  );
};

function ChangePasswordForm() {
  const [oldPassword, setOldPassword] = useState("");
  const [newPassword, setNewPassword] = useState("");
  const [message, setMessage] = useState("");
  const [error, setError] = useState("");
  const { token } = useAuth();
  const API_URL = process.env.NEXT_PUBLIC_API_URL || 'http://127.0.0.1:8000';

  const handleChangePassword = async (e: React.FormEvent) => {
    e.preventDefault();
    setMessage(""); setError("");
    try {
      const res = await fetch(`${API_URL}/api/auth/password/change/`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${token}` },
        body: JSON.stringify({ old_password: oldPassword, new_password: newPassword })
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error || 'Failed to update password');
      setMessage("Password updated successfully");
      setOldPassword(""); setNewPassword("");
    } catch (err: any) {
      setError(err.message);
    }
  };

  return (
    <form onSubmit={handleChangePassword} className="space-y-4">
      {message && <div className="text-green-600 bg-green-50 border border-green-200 p-3 rounded-lg text-sm">{message}</div>}
      {error && <div className="text-red-600 bg-red-50 border border-red-200 p-3 rounded-lg text-sm">{error}</div>}
      <div>
        <label className="block text-xs text-gray-500 mb-1">Current Password</label>
        <input type="password" value={oldPassword} onChange={(e) => setOldPassword(e.target.value)}
          className="w-full px-3 py-2 border border-gray-200 rounded-lg text-sm text-gray-700 bg-gray-50 focus:ring-2 focus:ring-[#2D8A4E] focus:border-transparent outline-none" required />
      </div>
      <div>
        <label className="block text-xs text-gray-500 mb-1">New Password</label>
        <input type="password" value={newPassword} onChange={(e) => setNewPassword(e.target.value)}
          className="w-full px-3 py-2 border border-gray-200 rounded-lg text-sm text-gray-700 bg-gray-50 focus:ring-2 focus:ring-[#2D8A4E] focus:border-transparent outline-none" required />
      </div>
      <button type="submit" className="bg-[#2D8A4E] text-white px-6 py-2 rounded-lg hover:bg-[#236b3d] transition-colors text-sm font-medium">
        Update Password
      </button>
    </form>
  );
}

export default ProfilePage;