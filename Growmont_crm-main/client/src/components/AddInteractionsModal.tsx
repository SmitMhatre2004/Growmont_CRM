'use client';

import { useEffect, useState } from 'react';
import toast from 'react-hot-toast';
import { api, endpoints } from '@/utils/api';

interface Props {
  isOpen: boolean;
  onClose: () => void;
  // onSave: () => void;
  onSave: (payload: any) => void;
  initialData?: any;
}

interface Employee {
  id: number;
  name: string;
  email: string;
  role: string;
}

export default function AddInteractionModal({ isOpen, onClose, onSave, initialData }: Props) {
  const [form, setForm] = useState({
    date: '',
    client_name: '',
    client_contact: '',
    employee: '',
    follow_up_date: '',
    follow_up_time: '',
    priority: 'MEDIUM',
    discussion_notes: '',
  });

  const payload = {
    ...form,
    follow_up_date: form.follow_up_date || null,
    follow_up_time: form.follow_up_time || null,
  };

  const [employees, setEmployees] = useState<Employee[]>([]);
  const [currentUser, setCurrentUser] = useState<any>(null);
  const [loading, setLoading] = useState(false);
  const [isEmployee, setIsEmployee] = useState(false);

  // Fetch current user and employees on mount
  useEffect(() => {
    if (isOpen) {
      fetchCurrentUser();
      fetchEmployees();
    }
  }, [isOpen]);

  // Reset form when modal opens/closes or initialData changes
  useEffect(() => {
    if (isOpen) {
      if (initialData) {
        // Edit mode
        setForm({
          date: initialData.date || '',
          client_name: initialData.client_name || '',
          client_contact: initialData.client_contact || '',
          employee: initialData.employee?.toString() || '',
          follow_up_date: initialData.follow_up_date || '',
          follow_up_time: initialData.follow_up_time || '',
          priority: initialData.priority || 'MEDIUM',
          discussion_notes: initialData.discussion_notes || '',
        });
      } else {
        // Add mode - set current date
        const today = new Date().toISOString().split('T')[0];
        setForm({
          date: today,
          client_name: '',
          client_contact: '',
          employee: currentUser?.id?.toString() || '',
          follow_up_date: '',
          follow_up_time: '',
          priority: 'MEDIUM',
          discussion_notes: '',
        });
      }
    }
  }, [isOpen, initialData, currentUser]);

  const fetchCurrentUser = async () => {
    try {
      const user = JSON.parse(localStorage.getItem('user') || '{}');
      setCurrentUser(user);
      setIsEmployee(user.role === 'EMPLOYEE');
      
      // Set employee to current user if they're an employee
      if (user.role === 'EMPLOYEE') {
        setForm(prev => ({ ...prev, employee: user.id.toString() }));
      }
    } catch (error) {
      console.error('Error fetching user:', error);
    }
  };

  const fetchEmployees = async () => {
    try {
      const data = await api.get('/api/employees/dropdown/');
      setEmployees(data);
    } catch (error) {
      console.error('Error fetching employees:', error);
      toast.error('Failed to load employees');
    }
  };

  if (!isOpen) return null;

  const handleChange = (e: any) => {
    setForm({ ...form, [e.target.name]: e.target.value });
  };

  const handleSubmit = async () => {
    // Validation
    if (!form.date || !form.client_name || !form.client_contact ||!form.follow_up_date || !form.follow_up_time) {
      toast.error('Please fill all required fields');
      return;
    }

    if (!form.employee) {
      toast.error('Please select a representative');
      return;
    }

    // Follow-up date and time must either both be provided or both be empty
    if (form.follow_up_date && !form.follow_up_time) {
      toast.error('Please select a follow-up time');
      return;
    }

    if (!form.follow_up_date && form.follow_up_time) {
      toast.error('Please select a follow-up date');
      return;
    }

    // Follow-up date cannot be before interaction date
    if (
      form.date &&
      form.follow_up_date &&
      form.follow_up_date < form.date
    ) {
      toast.error('Follow-up date cannot be before interaction date');
      return;
    }

    setLoading(true);

    try {
      if (initialData?.id) {
        // Update existing interaction
        await api.put(endpoints.updateInteraction(initialData.id), payload);
        toast.success('Interaction updated successfully!');
      } else {
        // Create new interaction
        await api.post(endpoints.createInteraction, payload);
        toast.success('Interaction created successfully!');
      }
      
      onSave(form); // Trigger parent to reload data
      onClose();
    } catch (error: any) {
      console.error('Error saving interaction:', error);
      toast.error(error.message || 'Failed to save interaction');
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/30 backdrop-blur-sm">
      <div className="w-full max-w-2xl rounded-2xl bg-white p-8 shadow-2xl max-h-[90vh] overflow-y-auto">

        {/* Header */}
        <div className="mb-6 flex justify-between items-center border-b pb-4">
          <h2 className="text-2xl font-bold text-gray-800">
            {initialData ? 'Edit Interaction' : 'Add New Interaction'}
          </h2>
          <button onClick={onClose} className="text-gray-500 hover:text-gray-700 transition">
            <svg xmlns="http://www.w3.org/2000/svg" className="h-6 w-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>

        <div className="space-y-4">

          {/* Date */}
          <div>
            <label className="block text-sm font-semibold text-gray-700 mb-1">
              Date <span className="text-red-500">*</span>
            </label>
            <input
              type="date"
              name="date"
              value={form.date}
              onChange={handleChange}
              className="w-full rounded-lg border border-gray-300 px-4 py-2 focus:ring-2 focus:ring-green-500 focus:border-transparent outline-none transition"
              required
            />
          </div>

          {/* Client Name & Contact */}
          <div className="grid grid-cols-2 gap-4">
            <div>
              <label className="block text-sm font-semibold text-gray-700 mb-1">
                Client Name <span className="text-red-500">*</span>
              </label>
              <input
                name="client_name"
                value={form.client_name}
                placeholder="Enter client name"
                onChange={handleChange}
                className="w-full rounded-lg border border-gray-300 px-4 py-2 focus:ring-2 focus:ring-green-500 focus:border-transparent outline-none transition"
                required
              />
            </div>
            <div>
              <label className="block text-sm font-semibold text-gray-700 mb-1">
                Client Contact <span className="text-red-500">*</span>
              </label>
              <input
                name="client_contact"
                value={form.client_contact}
                placeholder="Enter contact number"
                onChange={handleChange}
                className="w-full rounded-lg border border-gray-300 px-4 py-2 focus:ring-2 focus:ring-green-500 focus:border-transparent outline-none transition"
                required
              />
            </div>
          </div>

          {/* Representative */}
          <div>
            <label className="block text-sm font-semibold text-gray-700 mb-1">
              Representative <span className="text-red-500">*</span>
            </label>
            {isEmployee ? (
              <input
                type="text"
                value={currentUser?.name || 'Loading...'}
                disabled
                className="w-full rounded-lg border border-gray-300 px-4 py-2 bg-gray-100 text-gray-700 cursor-not-allowed"
              />
            ) : (
              <select
                name="employee"
                value={form.employee}
                onChange={handleChange}
                className="w-full rounded-lg border border-gray-300 px-4 py-2 focus:ring-2 focus:ring-green-500 focus:border-transparent outline-none transition"
                required
              >
                <option value="">Select representative</option>
                {employees.map((emp) => (
                  <option key={emp.id} value={emp.id}>
                    {emp.name} ({emp.role})
                  </option>
                ))}
              </select>
            )}
          </div>

          {/* Follow-up Date & Time */}
          <div className="grid grid-cols-2 gap-4">
            <div>
              <label className="block text-sm font-semibold text-gray-700 mb-1">
                Follow-up Date <span className="text-red-500">*</span>
              </label>
              <input
                type="date"
                name="follow_up_date"
                value={form.follow_up_date}
                onChange={handleChange}
                className="w-full rounded-lg border border-gray-300 px-4 py-2 focus:ring-2 focus:ring-green-500 focus:border-transparent outline-none transition"
                required
              />
            </div>
            <div>
              <label className="block text-sm font-semibold text-gray-700 mb-1">
                Follow-up Time <span className="text-red-500">*</span>
              </label>
              <input
                type="time"
                name="follow_up_time"
                value={form.follow_up_time}
                onChange={handleChange}
                className="w-full rounded-lg border border-gray-300 px-4 py-2 focus:ring-2 focus:ring-green-500 focus:border-transparent outline-none transition"
                required
              />
            </div>
          </div>

          {/* Priority */}
          <div>
            <label className="block text-sm font-semibold text-gray-700 mb-1">
              Priority <span className="text-red-500">*</span>
            </label>
            <select
              name="priority"
              value={form.priority}
              onChange={handleChange}
              className="w-full rounded-lg border border-gray-300 px-4 py-2 focus:ring-2 focus:ring-green-500 focus:border-transparent outline-none transition"
              required
            >
              <option value="HIGH">High</option>
              <option value="MEDIUM">Medium</option>
              <option value="LOW">Low</option>
            </select>
          </div>

          {/* Discussion Notes (Optional) */}
          <div>
            <label className="block text-sm font-semibold text-gray-700 mb-1">
              Discussion Notes (Optional)
            </label>
            <textarea
              name="discussion_notes"
              value={form.discussion_notes}
              placeholder="Enter details of the conversation..."
              onChange={handleChange}
              className="w-full rounded-lg border border-gray-300 px-4 py-2 focus:ring-2 focus:ring-green-500 focus:border-transparent outline-none transition"
              rows={3}
            />
          </div>

          {/* Submit Button */}
          <button
            onClick={handleSubmit}
            disabled={loading}
            className="w-full rounded-xl bg-[#2D8A4E] py-3 text-white font-semibold shadow-lg hover:bg-[#236b3d] hover:shadow-xl transition transform active:scale-95 disabled:opacity-50 disabled:cursor-not-allowed"
          >
            {loading ? 'Saving...' : initialData ? 'Update Interaction' : 'Save Interaction'}
          </button>
        </div>
      </div>
    </div>
  );
}