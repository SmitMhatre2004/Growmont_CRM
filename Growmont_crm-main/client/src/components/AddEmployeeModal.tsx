"use client";

import React, { useState, useEffect } from "react";
import toast from "react-hot-toast";

interface Employee {
  id: number;
  name: string;
  email: string;
  mobile_no: string;
  gender: string;
  dob: string;
  role: string;
  avatar: string | null;
}

interface AddEmployeeModalProps {
  isOpen: boolean;
  onClose: () => void;
  onSuccess?: () => void;
  initialData?: Employee | null;
}

const AddEmployeeModal: React.FC<AddEmployeeModalProps> = ({
  isOpen,
  onClose,
  onSuccess,
  initialData = null,
}) => {
  const [form, setForm] = useState({
    name: "",
    email: "",
    mobile_no: "",
    gender: "M",
    dob: "",
    role: "EMPLOYEE",
    password: "",
  });

  const [avatar, setAvatar] = useState<File | null>(null);
  const [loading, setLoading] = useState(false);
  const [showCredentials, setShowCredentials] = useState(false);
  const [credentials, setCredentials] = useState({ email: "", password: "" });

  // const API_URL = process.env.NEXT_PUBLIC_API_URL || 'http://127.0.0.1:8000';
const API_URL = "";

  // Pre-fill form when editing
  useEffect(() => {
    if (initialData) {
      setForm({
        name: initialData.name,
        email: initialData.email,
        mobile_no: initialData.mobile_no,
        gender: initialData.gender,
        dob: initialData.dob,
        role: initialData.role,
        password: "",
      });
    } else {
      // Reset form when adding new
      setForm({
        name: "",
        email: "",
        mobile_no: "",
        gender: "M",
        dob: "",
        role: "EMPLOYEE",
        password: "",
      });
      setAvatar(null);
    }
  }, [initialData, isOpen]);

  if (!isOpen) return null;

  const handleChange = (e: React.ChangeEvent<HTMLInputElement | HTMLSelectElement>) => {
    setForm({ ...form, [e.target.name]: e.target.value });
  };

  const generatePassword = () => {
    const length = 12;
    const charset = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*";
    let password = "";
    for (let i = 0; i < length; i++) {
      password += charset.charAt(Math.floor(Math.random() * charset.length));
    }
    setForm({ ...form, password });
    toast.success('Password generated!');
  };

  const handleSubmit = async () => {
    // Validation
    if (!form.name || !form.email || !form.mobile_no || !form.dob) {
      toast.error('Please fill all required fields');
      return;
    }

    if (!initialData && !form.password) {
      toast.error('Please create or generate a password');
      return;
    }

    setLoading(true);

    try {
      const token = localStorage.getItem('accessToken');
      
      if (!token) {
        toast.error('Please login first');
        window.location.href = '/';
        return;
      }

      const formData = new FormData();
      formData.append("name", form.name);
      formData.append("email", form.email);
      formData.append("mobile_no", form.mobile_no);
      formData.append("gender", form.gender);
      formData.append("dob", form.dob);
      formData.append("role", form.role);
      if (!initialData && form.password) {
        formData.append("password", form.password);
      }
      if (avatar) formData.append("avatar", avatar);

      let res;
      if (initialData) {
        // Update existing employee
        res = await fetch(`${API_URL}/api/employees/${initialData.id}/update/`, {
          method: "PUT",
          headers: {
            'Authorization': `Bearer ${token}`,
          },
          body: formData,
        });
      } else {
        // Create new employee
        res = await fetch(`${API_URL}/api/employees/`, {
          method: "POST",
          headers: {
            'Authorization': `Bearer ${token}`,
          },
          body: formData,
        });
      }

      const result = await res.json();

      if (!res.ok) {
        console.error("Backend error:", result);
        
        // Handle specific errors
        if (result.email) {
          toast.error(`Email: ${result.email[0]}`);
        } else if (result.error) {
          toast.error(result.error);
        } else {
          toast.error(initialData ? 'Failed to update employee' : 'Failed to add employee');
        }
        return;
      }

      if (initialData) {
        toast.success('Employee updated successfully!');
        onSuccess?.();
        onClose();
      } else {
        // Show credentials modal for new employee
        setCredentials({
          email: form.email,
          password: form.password,
        });
        setShowCredentials(true);
      }
      
    } catch (error) {
      console.error('Employee operation error:', error);
      toast.error(initialData ? 'Failed to update employee' : 'Failed to add employee');
    } finally {
      setLoading(false);
    }
  };

  const copyToClipboard = (text: string, label: string) => {
    navigator.clipboard.writeText(text);
    toast.success(`${label} copied to clipboard!`);
  };

  const copyAllCredentials = () => {
    const text = `Login Credentials:\n\nEmail: ${credentials.email}\nPassword: ${credentials.password}`;
    navigator.clipboard.writeText(text);
    toast.success('All credentials copied!');
  };

  const handleCredentialsClose = () => {
    setShowCredentials(false);
    setForm({
      name: "",
      email: "",
      mobile_no: "",
      gender: "M",
      dob: "",
      role: "EMPLOYEE",
      password: "",
    });
    setAvatar(null);
    onSuccess?.();
    onClose();
  };

  // Credentials Display Modal
  if (showCredentials) {
    return (
      <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 backdrop-blur-sm">
        <div className="w-full max-w-md rounded-2xl bg-white p-8 shadow-2xl">
          <div className="text-center mb-6">
            <div className="w-16 h-16 bg-green-100 rounded-full flex items-center justify-center mx-auto mb-4">
              <svg className="w-8 h-8 text-green-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 13l4 4L19 7" />
              </svg>
            </div>
            <h2 className="text-2xl font-bold text-gray-800 mb-2">Employee Created!</h2>
            <p className="text-gray-600">Save these credentials to share with the employee</p>
          </div>

          <div className="space-y-4 bg-gray-50 rounded-lg p-4">
            {/* Email */}
            <div>
              <label className="block text-xs font-semibold text-gray-500 mb-1">EMAIL / USERNAME</label>
              <div className="flex items-center gap-2">
                <input
                  type="text"
                  value={credentials.email}
                  readOnly
                  className="flex-1 px-3 py-2 bg-white border border-gray-300 rounded-lg text-sm font-mono"
                />
                <button
                  onClick={() => copyToClipboard(credentials.email, 'Email')}
                  className="p-2 bg-blue-500 text-white rounded-lg hover:bg-blue-600 transition"
                  title="Copy email"
                >
                  <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M8 16H6a2 2 0 01-2-2V6a2 2 0 012-2h8a2 2 0 012 2v2m-6 12h8a2 2 0 002-2v-8a2 2 0 00-2-2h-8a2 2 0 00-2 2v8a2 2 0 002 2z" />
                  </svg>
                </button>
              </div>
            </div>

            {/* Password */}
            <div>
              <label className="block text-xs font-semibold text-gray-500 mb-1">PASSWORD</label>
              <div className="flex items-center gap-2">
                <input
                  type="text"
                  value={credentials.password}
                  readOnly
                  className="flex-1 px-3 py-2 bg-white border border-gray-300 rounded-lg text-sm font-mono"
                />
                <button
                  onClick={() => copyToClipboard(credentials.password, 'Password')}
                  className="p-2 bg-blue-500 text-white rounded-lg hover:bg-blue-600 transition"
                  title="Copy password"
                >
                  <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M8 16H6a2 2 0 01-2-2V6a2 2 0 012-2h8a2 2 0 012 2v2m-6 12h8a2 2 0 002-2v-8a2 2 0 00-2-2h-8a2 2 0 00-2 2v8a2 2 0 002 2z" />
                  </svg>
                </button>
              </div>
            </div>
          </div>

          <div className="mt-6 space-y-3">
            <button
              onClick={copyAllCredentials}
              className="w-full py-3 bg-blue-500 text-white rounded-xl font-semibold hover:bg-blue-600 transition flex items-center justify-center gap-2"
            >
              <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M8 16H6a2 2 0 01-2-2V6a2 2 0 012-2h8a2 2 0 012 2v2m-6 12h8a2 2 0 002-2v-8a2 2 0 00-2-2h-8a2 2 0 00-2 2v8a2 2 0 002 2z" />
              </svg>
              Copy All Credentials
            </button>

            <button
              onClick={handleCredentialsClose}
              className="w-full py-3 bg-gray-200 text-gray-700 rounded-xl font-semibold hover:bg-gray-300 transition"
            >
              Done
            </button>
          </div>

          <div className="mt-4 bg-yellow-50 border border-yellow-200 rounded-lg p-3">
            <p className="text-xs text-yellow-800">
              <strong> Important:</strong> Save these credentials now. They won&apos;t be shown again!
            </p>
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/30 backdrop-blur-sm">
      <div className="w-full max-w-lg rounded-2xl bg-white p-8 shadow-2xl max-h-[90vh] overflow-y-auto">

        {/* Header */}
        <div className="mb-6 flex justify-between items-center border-b pb-4">
          <h2 className="text-2xl font-bold text-gray-800">
            {initialData ? 'Edit Employee' : 'Add Employee'}
          </h2>
          <button 
            onClick={onClose} 
            className="text-gray-500 hover:text-gray-700 transition"
            disabled={loading}
          >
            <svg xmlns="http://www.w3.org/2000/svg" className="h-6 w-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>

        {/* Form */}
        <div className="space-y-4">

          <div>
            <label className="block text-sm font-semibold text-gray-700 mb-1">
              Employee Name <span className="text-red-500">*</span>
            </label>
            <input
              name="name"
              value={form.name}
              onChange={handleChange}
              placeholder="Enter full name"
              className="w-full rounded-lg border border-gray-300 px-4 py-2 focus:ring-2 focus:ring-green-500 focus:border-transparent outline-none transition"
              required
            />
          </div>

          <div>
            <label className="block text-sm font-semibold text-gray-700 mb-1">
              Email <span className="text-red-500">*</span>
            </label>
            <input
              name="email"
              value={form.email}
              onChange={handleChange}
              placeholder="employee@example.com"
              type="email"
              className="w-full rounded-lg border border-gray-300 px-4 py-2 focus:ring-2 focus:ring-green-500 focus:border-transparent outline-none transition"
              required
              disabled={!!initialData}
            />
            {initialData && (
              <p className="text-xs text-gray-500 mt-1">Email cannot be changed</p>
            )}
          </div>

          <div>
            <label className="block text-sm font-semibold text-gray-700 mb-1">
              Mobile Number <span className="text-red-500">*</span>
            </label>
            <input
              name="mobile_no"
              value={form.mobile_no}
              onChange={handleChange}
              placeholder="Enter mobile number"
              className="w-full rounded-lg border border-gray-300 px-4 py-2 focus:ring-2 focus:ring-green-500 focus:border-transparent outline-none transition"
              required
            />
          </div>

          {/* Gender */}
          <div>
            <label className="block text-sm font-semibold text-gray-700 mb-1">
              Gender <span className="text-red-500">*</span>
            </label>
            <div className="flex gap-2">
              {[
                { label: "Male", value: "M" },
                { label: "Female", value: "F" },
                { label: "Other", value: "O" },
              ].map(g => (
                <button
                  key={g.value}
                  type="button"
                  onClick={() => setForm({ ...form, gender: g.value })}
                  className={`flex-1 rounded-lg border px-3 py-2 text-sm transition font-medium
                    ${form.gender === g.value
                      ? "bg-[#2D8A4E] text-white border-[#2D8A4E]"
                      : "border-gray-300 text-gray-700 hover:bg-gray-50"}`}
                >
                  {g.label}
                </button>
              ))}
            </div>
          </div>

          <div>
            <label className="block text-sm font-semibold text-gray-700 mb-1">
              Date of Birth <span className="text-red-500">*</span>
            </label>
            <input
              name="dob"
              value={form.dob}
              onChange={handleChange}
              type="date"
              className="w-full rounded-lg border border-gray-300 px-4 py-2 focus:ring-2 focus:ring-green-500 focus:border-transparent outline-none transition"
              required
            />
          </div>

          {/* Role */}
          <div>
            <label className="block text-sm font-semibold text-gray-700 mb-1">
              Role <span className="text-red-500">*</span>
            </label>
            <select
              name="role"
              value={form.role}
              onChange={handleChange}
              className="w-full rounded-lg border border-gray-300 px-4 py-2 focus:ring-2 focus:ring-green-500 focus:border-transparent outline-none transition"
            >
              <option value="EMPLOYEE">Employee</option>
              <option value="ADMIN">Admin</option>
            </select>
          </div>

          {/* Password (only for new employees) */}
          {!initialData && (
            <div>
              <label className="block text-sm font-semibold text-gray-700 mb-1">
                Password <span className="text-red-500">*</span>
              </label>
              <div className="flex gap-2">
                <input
                  name="password"
                  type="text"
                  value={form.password}
                  onChange={handleChange}
                  placeholder="Enter or generate password"
                  className="flex-1 rounded-lg border border-gray-300 px-4 py-2 focus:ring-2 focus:ring-green-500 focus:border-transparent outline-none transition"
                  required
                />
                <button
                  type="button"
                  onClick={generatePassword}
                  className="px-4 py-2 bg-[#00337C] text-white rounded-lg  transition font-medium whitespace-nowrap"
                >
                   Generate
                </button>
              </div>
              <p className="text-xs text-gray-500 mt-1">Create a password or click generate</p>
            </div>
          )}

          {/* Avatar */}
          <div>
            <label className="block text-sm font-semibold text-gray-700 mb-1">
              Avatar (Optional)
            </label>
            <input
              type="file"
              accept="image/*"
              onChange={(e) => setAvatar(e.target.files?.[0] || null)}
              className="w-full text-sm text-gray-500 file:mr-4 file:py-2 file:px-4 file:rounded-full file:border-0 file:text-sm file:font-semibold file:bg-green-50 file:text-green-700 hover:file:bg-green-100"
            />
          </div>

          {!initialData && (
            <div className="bg-blue-50 border border-blue-200 rounded-lg p-3">
              <p className="text-sm text-[#00337C]">
                <strong> Note:</strong> After creating the employee, you&apos;ll see their credentials which you can copy and share with them.
              </p>
            </div>
          )}

          <button
            onClick={handleSubmit}
            disabled={loading}
            className="w-full rounded-xl bg-[#2D8A4E] py-3 text-white font-semibold shadow-lg hover:bg-[#236b3d] hover:shadow-xl transition transform active:scale-95 disabled:opacity-70 disabled:cursor-not-allowed"
          >
            {loading 
              ? (initialData ? "Updating..." : "Creating...") 
              : (initialData ? "Update Employee" : "Create Employee")
            }
          </button>
        </div>
      </div>
    </div>
  );
};

export default AddEmployeeModal;