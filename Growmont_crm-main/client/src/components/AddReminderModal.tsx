"use client";

import React, { useState, useEffect } from "react";
import { useAuth } from "@/context/AuthContext";

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

interface AddReminderModalProps {
  isOpen: boolean;
  onClose: () => void;
  onReminderAdded?: () => void;
  editingReminder?: Reminder | null;
}

const AddReminderModal: React.FC<AddReminderModalProps> = ({
  isOpen,
  onClose,
  onReminderAdded,
  editingReminder = null,
}) => {
  const { user } = useAuth();
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");

  // Form state
  const [eventName, setEventName] = useState("");
  const [type, setType] = useState("CORPORATE");
  const [priority, setPriority] = useState("MEDIUM");
  const [date, setDate] = useState("");
  const [time, setTime] = useState("");
  const [endTime, setEndTime] = useState("");
  const [description, setDescription] = useState("");
  const [repeatReminder, setRepeatReminder] = useState(false);
  const [repeatType, setRepeatType] = useState("NONE");
  const [selectedDays, setSelectedDays] = useState<string[]>([]);
  const [repeatEveryDay, setRepeatEveryDay] = useState(false);

  // const API_URL = process.env.NEXT_PUBLIC_API_URL || 'http://127.0.0.1:8000';
const API_URL = "";

  // Prefill form when editing
  useEffect(() => {
    if (editingReminder) {
      setEventName(editingReminder.event_name);
      setType(editingReminder.type);
      setPriority(editingReminder.priority);
      setDate(editingReminder.date);
      setTime(editingReminder.time);
      setEndTime(editingReminder.end_time || "");
      setDescription(editingReminder.description || "");
      setRepeatReminder(editingReminder.repeat_reminder);
      setRepeatType(editingReminder.repeat_type || "NONE");
      setSelectedDays(editingReminder.repeat_days || []);
      setRepeatEveryDay(editingReminder.repeat_every_day);
    }
  }, [editingReminder]);

  if (!isOpen) return null;

  const handleSave = async (e: React.FormEvent) => {
    e.preventDefault();
    setError("");
    setLoading(true);

    try {
      const token = localStorage.getItem('accessToken');

      const payload = {
        employee: user?.id,
        event_name: eventName,
        type,
        priority,
        date,
        time,
        end_time: endTime || null,
        description,
        repeat_reminder: repeatReminder,
        repeat_type: repeatReminder ? repeatType : "NONE",
        repeat_days: repeatReminder ? selectedDays : [],
        repeat_every_day: repeatEveryDay,
      };

      // Determine if creating or updating
      const url = editingReminder 
        ? `${API_URL}/api/reminders/${editingReminder.id}/update/`
        : `${API_URL}/api/reminders/create/`;
      
      const method = editingReminder ? 'PUT' : 'POST';

      const res = await fetch(url, {
        method,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${token}`
        },
        body: JSON.stringify(payload)
      });

      if (!res.ok) {
        const errorData = await res.json();
        throw new Error(errorData.error || `Failed to ${editingReminder ? 'update' : 'create'} reminder`);
      }

      // Success - reset form
      resetForm();
      onClose();
      
      // Notify parent to refresh data
      if (onReminderAdded) {
        onReminderAdded();
      }
    } catch (err: any) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  };

  const resetForm = () => {
    setEventName("");
    setType("CORPORATE");
    setPriority("MEDIUM");
    setDate("");
    setTime("");
    setEndTime("");
    setDescription("");
    setRepeatReminder(false);
    setRepeatType("NONE");
    setSelectedDays([]);
    setRepeatEveryDay(false);
    setError("");
  };

  const toggleDay = (day: string) => {
    setSelectedDays(prev => 
      prev.includes(day) 
        ? prev.filter(d => d !== day) 
        : [...prev, day]
    );
  };

  const handleClose = () => {
    resetForm();
    onClose();
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 backdrop-blur-sm">
      <div className="w-full max-w-lg rounded-2xl bg-white p-8 shadow-2xl max-h-[90vh] overflow-y-auto">
        {/* Header */}
        <div className="mb-6 flex justify-between items-center border-b border-gray-200 pb-4">
          <h2 className="text-2xl font-bold text-gray-800">
            {editingReminder ? 'Edit Reminder' : 'Add Reminder'}
          </h2>
          <button 
            onClick={handleClose} 
            className="text-gray-400 hover:text-gray-600 transition p-2 hover:bg-gray-100 rounded-lg"
            type="button"
          >
            <svg className="h-6 w-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>

        {error && (
          <div className="mb-4 bg-red-50 border border-red-200 text-red-700 p-3 rounded-lg text-sm">
            {error}
          </div>
        )}

        <form onSubmit={handleSave} className="space-y-4">
          <div>
            <label className="block text-sm font-semibold text-gray-700 mb-1">
              Event Name *
            </label>
            <input
              type="text"
              value={eventName}
              onChange={(e) => setEventName(e.target.value)}
              placeholder="Enter event name"
              className="w-full rounded-lg border border-gray-300 px-4 py-2 focus:ring-2 focus:ring-green-500 focus:border-transparent outline-none transition"
              required
            />
          </div>

          <div className="grid grid-cols-2 gap-4">
            <div>
              <label className="block text-sm font-semibold text-gray-700 mb-1">Type *</label>
              <select 
                value={type}
                onChange={(e) => setType(e.target.value)}
                className="w-full rounded-lg border border-gray-300 px-4 py-2 focus:ring-2 focus:ring-green-500 focus:border-transparent outline-none transition bg-white"
                required
              >
                <option value="CORPORATE">Corporate Event</option>
                <option value="PERSONAL">Personal</option>
              </select>
            </div>
            <div>
              <label className="block text-sm font-semibold text-gray-700 mb-1">Priority *</label>
              <select 
                value={priority}
                onChange={(e) => setPriority(e.target.value)}
                className="w-full rounded-lg border border-gray-300 px-4 py-2 focus:ring-2 focus:ring-green-500 focus:border-transparent outline-none transition bg-white"
                required
              >
                <option value="HIGH">High Priority</option>
                <option value="MEDIUM">Medium Priority</option>
                <option value="LOW">Low Priority</option>
              </select>
            </div>
          </div>

          <div className="grid grid-cols-2 gap-4">
            <div>
              <label className="block text-sm font-semibold text-gray-700 mb-1">Date *</label>
              <input
                type="date"
                value={date}
                onChange={(e) => setDate(e.target.value)}
                className="w-full rounded-lg border border-gray-300 px-4 py-2 focus:ring-2 focus:ring-green-500 focus:border-transparent outline-none transition"
                required
              />
            </div>
            <div>
              <label className="block text-sm font-semibold text-gray-700 mb-1">Time *</label>
              <input
                type="time"
                value={time}
                onChange={(e) => setTime(e.target.value)}
                className="w-full rounded-lg border border-gray-300 px-4 py-2 focus:ring-2 focus:ring-green-500 focus:border-transparent outline-none transition"
                required
              />
            </div>
          </div>

          <div>
            <label className="block text-sm font-semibold text-gray-700 mb-1">Description</label>
            <textarea
              value={description}
              onChange={(e) => setDescription(e.target.value)}
              placeholder="Add some description of the event"
              className="w-full rounded-lg border border-gray-300 px-4 py-2 focus:ring-2 focus:ring-green-500 focus:border-transparent outline-none transition resize-none"
              rows={3}
            />
          </div>

          {/* Repeat */}
          <div className="flex items-center justify-between rounded-lg bg-gray-50 px-4 py-3 border border-gray-100">
            <span className="font-medium text-gray-700">Repeat Reminder</span>
            <input 
              type="checkbox" 
              checked={repeatReminder}
              onChange={(e) => setRepeatReminder(e.target.checked)}
              className="h-5 w-5 accent-green-600 rounded" 
            />
          </div>

          {repeatReminder && (
            <>
              <div className="flex gap-2">
                {[
                  { value: "DAILY", label: "Daily" },
                  { value: "WEEKLY", label: "Weekly" },
                  { value: "MONTHLY", label: "Monthly" }
                ].map((r) => (
                  <button
                    key={r.value}
                    type="button"
                    onClick={() => setRepeatType(r.value)}
                    className={`flex-1 rounded-lg border px-3 py-2 text-sm font-medium transition ${
                      repeatType === r.value
                        ? "bg-green-600 text-white border-green-600" 
                        : "border-gray-300 hover:bg-green-600 hover:text-white hover:border-green-600"
                    }`}
                  >
                    {r.label}
                  </button>
                ))}
              </div>

              <div className="flex flex-wrap gap-2">
                {["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"].map((d) => (
                  <button
                    key={d}
                    type="button"
                    onClick={() => toggleDay(d)}
                    className={`rounded-md px-3 py-1 text-sm font-medium transition ${
                      selectedDays.includes(d)
                        ? "bg-green-600 text-white"
                        : "bg-gray-100 hover:bg-green-600 hover:text-white"
                    }`}
                  >
                    {d}
                  </button>
                ))}
              </div>

              <label className="flex items-center gap-2 text-sm text-gray-600">
                <input 
                  type="checkbox" 
                  checked={repeatEveryDay}
                  onChange={(e) => setRepeatEveryDay(e.target.checked)}
                  className="rounded text-green-600 focus:ring-green-500" 
                /> 
                Repeat every day
              </label>
            </>
          )}

          <div>
            <label className="block text-sm font-semibold text-gray-700 mb-1">End Time</label>
            <input
              type="time"
              value={endTime}
              onChange={(e) => setEndTime(e.target.value)}
              className="w-full rounded-lg border border-gray-300 px-4 py-2 focus:ring-2 focus:ring-green-500 focus:border-transparent outline-none transition"
            />
          </div>

          <div className="flex gap-3 pt-2">
            <button
              type="button"
              onClick={handleClose}
              className="flex-1 rounded-xl bg-gray-100 py-3 text-gray-700 font-semibold hover:bg-gray-200 transition"
              disabled={loading}
            >
              Cancel
            </button>
            <button 
              type="submit"
              disabled={loading}
              className="flex-1 rounded-xl bg-[#2D8A4E] py-3 text-white font-semibold shadow-lg hover:bg-[#236b3d] hover:shadow-xl transition transform active:scale-95 disabled:opacity-50 disabled:cursor-not-allowed"
            >
              {loading ? (editingReminder ? 'Updating...' : 'Saving...') : (editingReminder ? 'Update Reminder' : 'Save Event')}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
};

export default AddReminderModal;