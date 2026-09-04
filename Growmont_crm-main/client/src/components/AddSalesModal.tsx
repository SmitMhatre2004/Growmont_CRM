// 'use client';

// import { useEffect, useState } from 'react';
// import toast from 'react-hot-toast';
// import { api, endpoints } from '@/utils/api';

// interface Props {
//   isOpen: boolean;
//   onClose: () => void;
//   // onSave: () => void;
//   onSave: (payload: any) => void;
//   initialData?: any;
// }

// interface Employee {
//   id: number;
//   name: string;
//   email: string;
//   role: string;
// }

// export default function AddSalesModal({ isOpen, onClose, onSave, initialData }: Props) {
//   const [form, setForm] = useState({
//     date: '',
//     client_name: '',
//     sales_rep: '',
//     product: 'MF',
//     company: '',
//     scheme: '',
//     amount: '',
//     frequency: 'M',
//     remarks: '',
//   });

//   const [employees, setEmployees] = useState<Employee[]>([]);
//   const [currentUser, setCurrentUser] = useState<any>(null);
//   const [loading, setLoading] = useState(false);
//   const [isEmployee, setIsEmployee] = useState(false);

//   // Fetch current user and employees on mount
//   useEffect(() => {
//     if (isOpen) {
//       fetchCurrentUser();
//       fetchEmployees();
//     }
//   }, [isOpen]);

//   // Reset form when modal opens/closes or initialData changes
//   useEffect(() => {
//     if (isOpen) {
//       if (initialData) {
//         // Edit mode
//         setForm({
//           date: initialData.date || '',
//           client_name: initialData.client_name || '',
//           sales_rep: initialData.sales_rep?.toString() || '',
//           product: initialData.product || 'MF',
//           company: initialData.company || '',
//           scheme: initialData.scheme || '',
//           amount: initialData.amount || '',
//           frequency: initialData.frequency || 'M',
//           remarks: initialData.remarks || '',
//         });
//       } else {
//         // Add mode - set current date
//         const today = new Date().toISOString().split('T')[0];
//         setForm({
//           date: today,
//           client_name: '',
//           sales_rep: currentUser?.id?.toString() || '',
//           product: 'MF',
//           company: '',
//           scheme: '',
//           amount: '',
//           frequency: 'M',
//           remarks: '',
//         });
//       }
//     }
//   }, [isOpen, initialData, currentUser]);

//   const fetchCurrentUser = async () => {
//     try {
//       const user = JSON.parse(localStorage.getItem('user') || '{}');
//       setCurrentUser(user);
//       setIsEmployee(user.role === 'EMPLOYEE');
      
//       // Set sales_rep to current user if they're an employee
//       if (user.role === 'EMPLOYEE') {
//         setForm(prev => ({ ...prev, sales_rep: user.id.toString() }));
//       }
//     } catch (error) {
//       console.error('Error fetching user:', error);
//     }
//   };

//   const fetchEmployees = async () => {
//     try {
//       const data = await api.get('/api/employees/dropdown/');
//       setEmployees(data);
//     } catch (error) {
//       console.error('Error fetching employees:', error);
//       toast.error('Failed to load employees');
//     }
//   };

//   if (!isOpen) return null;

//   const handleChange = (e: any) => {
//     setForm({ ...form, [e.target.name]: e.target.value });
//   };

//   const handleSubmit = async () => {
//     // Validation
//     if (!form.date || !form.client_name || !form.product || !form.company || !form.scheme || !form.amount || !form.frequency) {
//       toast.error('Please fill all required fields');
//       return;
//     }

//     if (!form.sales_rep) {
//       toast.error('Please select a sales representative');
//       return;
//     }

//     setLoading(true);

//     try {
//       if (initialData?.id) {
//         // Update existing sale
//         await api.put(endpoints.updateSale(initialData.id), form);
//         toast.success('Sale updated successfully!');
//       } else {
//         // Create new sale
//         await api.post(endpoints.createSale, form);
//         toast.success('Sale created successfully!');
//       }
      
//       onSave(form); // Trigger parent to reload data
//       onClose();
//     } catch (error: any) {
//       console.error('Error saving sale:', error);
//       toast.error(error.message || 'Failed to save sale');
//     } finally {
//       setLoading(false);
//     }
//   };

//   return (
//     <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/30 backdrop-blur-sm">
//       <div className="w-full max-w-3xl rounded-2xl bg-white p-8 shadow-2xl max-h-[90vh] overflow-y-auto">

//         {/* Header */}
//         <div className="mb-6 flex justify-between items-center border-b pb-4">
//           <h2 className="text-2xl font-bold text-gray-800">
//             {initialData ? 'Edit Sale' : 'Add New Sale'}
//           </h2>
//           <button onClick={onClose} className="text-gray-500 hover:text-gray-700 transition">
//             <svg xmlns="http://www.w3.org/2000/svg" className="h-6 w-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
//               <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
//             </svg>
//           </button>
//         </div>

//         <div className="space-y-4">

//           {/* Row 1: Date & Client Name */}
//           <div className="grid grid-cols-2 gap-4">
//             <div>
//               <label className="block text-sm font-semibold text-gray-700 mb-1">
//                 Date <span className="text-red-500">*</span>
//               </label>
//               <input
//                 type="date"
//                 name="date"
//                 value={form.date}
//                 onChange={handleChange}
//                 className="w-full rounded-lg border border-gray-300 px-4 py-2 focus:ring-2 focus:ring-green-500 focus:border-transparent outline-none transition"
//                 required
//               />
//             </div>
//             <div>
//               <label className="block text-sm font-semibold text-gray-700 mb-1">
//                 Client Name <span className="text-red-500">*</span>
//               </label>
//               <input
//                 name="client_name"
//                 value={form.client_name}
//                 placeholder="Enter client name"
//                 onChange={handleChange}
//                 className="w-full rounded-lg border border-gray-300 px-4 py-2 focus:ring-2 focus:ring-green-500 focus:border-transparent outline-none transition"
//                 required
//               />
//             </div>
//           </div>

//           {/* Row 2: Sales Representative */}
//           <div>
//             <label className="block text-sm font-semibold text-gray-700 mb-1">
//               Sales Representative <span className="text-red-500">*</span>
//             </label>
//             {isEmployee ? (
//               <input
//                 type="text"
//                 value={currentUser?.name || 'Loading...'}
//                 disabled
//                 className="w-full rounded-lg border border-gray-300 px-4 py-2 bg-gray-100 text-gray-700 cursor-not-allowed"
//               />
//             ) : (
//               <select
//                 name="sales_rep"
//                 value={form.sales_rep}
//                 onChange={handleChange}
//                 className="w-full rounded-lg border border-gray-300 px-4 py-2 focus:ring-2 focus:ring-green-500 focus:border-transparent outline-none transition"
//                 required
//               >
//                 <option value="">Select sales representative</option>
//                 {employees.map((emp) => (
//                   <option key={emp.id} value={emp.id}>
//                     {emp.name} ({emp.role})
//                   </option>
//                 ))}
//               </select>
//             )}
//           </div>

//           {/* Row 3: Product & Company */}
//           <div className="grid grid-cols-2 gap-4">
//             <div>
//               <label className="block text-sm font-semibold text-gray-700 mb-1">
//                 Product <span className="text-red-500">*</span>
//               </label>
//               <select
//                 name="product"
//                 value={form.product}
//                 onChange={handleChange}
//                 className="w-full rounded-lg border border-gray-300 px-4 py-2 focus:ring-2 focus:ring-green-500 focus:border-transparent outline-none transition"
//                 required
//               >
//                 <option value="MF">Mutual Funds</option>
//                 <option value="HI">Health Insurance</option>
//                 <option value="GI">General Insurance</option>
//                 <option value="LI">Life Insurance</option>
//                 <option value="NCD">NCDs</option>
//                 <option value="MLD">MLDs</option>
//                 <option value="BOND">Bonds</option>
//                 <option value="CFD">Corporate FDs</option>
//                 <option value="AIF">AIFs</option>
//                 <option value="PMS">PMS</option>
//                 <option value="ADV">Advisory</option>
//                 <option value="SB">Shares Broking</option>
//                 <option value="US">Unlisted Shares</option>
//                 <option value="RE">Real Estate</option>
//                 <option value="LOAN">Loans</option>
//                 <option value="WILL">Will Making</option>
//               </select>
//             </div>
//             <div>
//               <label className="block text-sm font-semibold text-gray-700 mb-1">
//                 Company <span className="text-red-500">*</span>
//               </label>
//               <input
//                 name="company"
//                 value={form.company}
//                 placeholder="Enter company name"
//                 onChange={handleChange}
//                 className="w-full rounded-lg border border-gray-300 px-4 py-2 focus:ring-2 focus:ring-green-500 focus:border-transparent outline-none transition"
//                 required
//               />
//             </div>
//           </div>

//           {/* Row 4: Scheme */}
//           <div>
//             <label className="block text-sm font-semibold text-gray-700 mb-1">
//               Scheme <span className="text-red-500">*</span>
//             </label>
//             <input
//               name="scheme"
//               value={form.scheme}
//               placeholder="Enter scheme name"
//               onChange={handleChange}
//               className="w-full rounded-lg border border-gray-300 px-4 py-2 focus:ring-2 focus:ring-green-500 focus:border-transparent outline-none transition"
//               required
//             />
//           </div>

//           {/* Row 5: Amount & Frequency */}
//           <div className="grid grid-cols-2 gap-4">
//             <div>
//               <label className="block text-sm font-semibold text-gray-700 mb-1">
//                 Amount <span className="text-red-500">*</span>
//               </label>
//               <input
//                 type="number"
//                 name="amount"
//                 value={form.amount}
//                 placeholder="0.00"
//                 onChange={handleChange}
//                 className="w-full rounded-lg border border-gray-300 px-4 py-2 focus:ring-2 focus:ring-green-500 focus:border-transparent outline-none transition"
//                 required
//               />
//             </div>
//             <div>
//               <label className="block text-sm font-semibold text-gray-700 mb-1">
//                 Frequency <span className="text-red-500">*</span>
//               </label>
//               <select
//                 name="frequency"
//                 value={form.frequency}
//                 onChange={handleChange}
//                 className="w-full rounded-lg border border-gray-300 px-4 py-2 focus:ring-2 focus:ring-green-500 focus:border-transparent outline-none transition"
//                 required
//               >
//                 <option value="M">Monthly</option>
//                 <option value="Q">Quarterly</option>
//                 <option value="H">Half Yearly</option>
//                 <option value="Y">Yearly</option>
//                 <option value="O">One Time</option>
//               </select>
//             </div>
//           </div>

//           {/* Remarks (Optional) */}
//           <div>
//             <label className="block text-sm font-semibold text-gray-700 mb-1">
//               Remarks (Optional)
//             </label>
//             <textarea
//               name="remarks"
//               value={form.remarks}
//               placeholder="Enter any additional notes..."
//               onChange={handleChange}
//               className="w-full rounded-lg border border-gray-300 px-4 py-2 focus:ring-2 focus:ring-green-500 focus:border-transparent outline-none transition"
//               rows={3}
//             />
//           </div>

//           {/* Submit Button */}
//           <button
//             onClick={handleSubmit}
//             disabled={loading}
//             className="w-full rounded-xl bg-[#2D8A4E] py-3 text-white font-semibold shadow-lg hover:bg-[#236b3d] hover:shadow-xl transition transform active:scale-95 disabled:opacity-50 disabled:cursor-not-allowed"
//           >
//             {loading ? 'Saving...' : initialData ? 'Update Sale' : 'Save Sale'}
//           </button>
//         </div>
//       </div>
//     </div>
//   );
// }


'use client';

import { useEffect, useState } from 'react';
import toast from 'react-hot-toast';
import { api, endpoints } from '@/utils/api';

interface Props {
  isOpen: boolean;
  onClose: () => void;
  onSave: (payload: any) => void;
  initialData?: any;
}

interface Employee {
  id: number;
  name: string;
  email: string;
  role: string;
}

export default function AddSalesModal({ isOpen, onClose, onSave, initialData }: Props) {
  const [form, setForm] = useState({
    date: '',
    client_name: '',
    sales_rep: '',
    product: 'MF',
    company: '',
    scheme: '',
    amount: '',
    frequency: 'M',
    remarks: '',
  });

  const [employees, setEmployees] = useState<Employee[]>([]);
  const [currentUser, setCurrentUser] = useState<any>(null);
  const [loading, setLoading] = useState(false);
  const [isEmployee, setIsEmployee] = useState(false);

  useEffect(() => {
    if (isOpen) {
      fetchCurrentUser();
      fetchEmployees();
    }
  }, [isOpen]);

  useEffect(() => {
    if (isOpen) {
      if (initialData) {
        setForm({
          date: initialData.date || '',
          client_name: initialData.client_name || '',
          sales_rep: initialData.sales_rep?.toString() || '',
          product: initialData.product || 'MF',
          company: initialData.company || '',
          scheme: initialData.scheme || '',
          amount: initialData.amount || '',
          frequency: initialData.frequency || 'M',
          remarks: initialData.remarks || '',
        });
      } else {
        const today = new Date().toISOString().split('T')[0];
        setForm({
          date: today,
          client_name: '',
          sales_rep: currentUser?.id?.toString() || '',
          product: 'MF',
          company: '',
          scheme: '',
          amount: '',
          frequency: 'M',
          remarks: '',
        });
      }
    }
  }, [isOpen, initialData, currentUser]);

  const fetchCurrentUser = async () => {
    try {
      const user = JSON.parse(localStorage.getItem('user') || '{}');
      setCurrentUser(user);
      setIsEmployee(user.role === 'EMPLOYEE');
      if (user.role === 'EMPLOYEE') {
        setForm(prev => ({ ...prev, sales_rep: user.id.toString() }));
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
    if (!form.date || !form.client_name || !form.product || !form.company || !form.scheme || !form.amount || !form.frequency) {
      toast.error('Please fill all required fields');
      return;
    }
    if (!form.sales_rep) {
      toast.error('Please select a sales representative');
      return;
    }

    setLoading(true);
    try {
      if (initialData?.id) {
        await api.put(endpoints.updateSale(initialData.id), form);
        toast.success('Sale updated successfully!');
      } else {
        await api.post(endpoints.createSale, form);
        toast.success('Sale created successfully!');
      }
      onSave(form);
      onClose();
    } catch (error: any) {
      console.error('Error saving sale:', error);
      toast.error(error.message || 'Failed to save sale');
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="fixed inset-0 z-50 flex items-end sm:items-center justify-center bg-black/30 backdrop-blur-sm px-0 sm:px-4 mx-auto">
      <div className="w-full sm:max-w-3xl rounded-t-2xl sm:rounded-2xl bg-white p-5 sm:p-8 shadow-2xl max-h-[92vh] overflow-y-auto">

        {/* Header */}
        <div className="mb-5 flex justify-between items-center border-b pb-4">
          <h2 className="text-xl sm:text-2xl font-bold text-gray-800">
            {initialData ? 'Edit Sale' : 'Add New Sale'}
          </h2>
          <button onClick={onClose} className="text-gray-500 hover:text-gray-700 transition p-1">
            <svg xmlns="http://www.w3.org/2000/svg" className="h-6 w-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>

        <div className="space-y-4">

          {/* Row 1: Date & Client Name */}
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
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
          </div>

          {/* Row 2: Sales Representative */}
          <div>
            <label className="block text-sm font-semibold text-gray-700 mb-1">
              Sales Representative <span className="text-red-500">*</span>
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
                name="sales_rep"
                value={form.sales_rep}
                onChange={handleChange}
                className="w-full rounded-lg border border-gray-300 px-4 py-2 focus:ring-2 focus:ring-green-500 focus:border-transparent outline-none transition"
                required
              >
                <option value="">Select sales representative</option>
                {employees.map((emp) => (
                  <option key={emp.id} value={emp.id}>
                    {emp.name} ({emp.role})
                  </option>
                ))}
              </select>
            )}
          </div>

          {/* Row 3: Product & Company */}
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <div>
              <label className="block text-sm font-semibold text-gray-700 mb-1">
                Product <span className="text-red-500">*</span>
              </label>
              <select
                name="product"
                value={form.product}
                onChange={handleChange}
                className="w-full rounded-lg border border-gray-300 px-4 py-2 focus:ring-2 focus:ring-green-500 focus:border-transparent outline-none transition"
                required
              >
                <option value="MF">Mutual Funds</option>
                <option value="HI">Health Insurance</option>
                <option value="GI">General Insurance</option>
                <option value="LI">Life Insurance</option>
                <option value="NCD">NCDs</option>
                <option value="MLD">MLDs</option>
                <option value="BOND">Bonds</option>
                <option value="CFD">Corporate FDs</option>
                <option value="AIF">AIFs</option>
                <option value="PMS">PMS</option>
                <option value="ADV">Advisory</option>
                <option value="SB">Shares Broking</option>
                <option value="US">Unlisted Shares</option>
                <option value="RE">Real Estate</option>
                <option value="LOAN">Loans</option>
                <option value="WILL">Will Making</option>
              </select>
            </div>
            <div>
              <label className="block text-sm font-semibold text-gray-700 mb-1">
                Company <span className="text-red-500">*</span>
              </label>
              <input
                name="company"
                value={form.company}
                placeholder="Enter company name"
                onChange={handleChange}
                className="w-full rounded-lg border border-gray-300 px-4 py-2 focus:ring-2 focus:ring-green-500 focus:border-transparent outline-none transition"
                required
              />
            </div>
          </div>

          {/* Row 4: Scheme */}
          <div>
            <label className="block text-sm font-semibold text-gray-700 mb-1">
              Scheme <span className="text-red-500">*</span>
            </label>
            <input
              name="scheme"
              value={form.scheme}
              placeholder="Enter scheme name"
              onChange={handleChange}
              className="w-full rounded-lg border border-gray-300 px-4 py-2 focus:ring-2 focus:ring-green-500 focus:border-transparent outline-none transition"
              required
            />
          </div>

          {/* Row 5: Amount & Frequency */}
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <div>
              <label className="block text-sm font-semibold text-gray-700 mb-1">
                Amount <span className="text-red-500">*</span>
              </label>
              <input
                type="number"
                name="amount"
                value={form.amount}
                placeholder="0.00"
                onChange={handleChange}
                className="w-full rounded-lg border border-gray-300 px-4 py-2 focus:ring-2 focus:ring-green-500 focus:border-transparent outline-none transition"
                required
              />
            </div>
            <div>
              <label className="block text-sm font-semibold text-gray-700 mb-1">
                Frequency <span className="text-red-500">*</span>
              </label>
              <select
                name="frequency"
                value={form.frequency}
                onChange={handleChange}
                className="w-full rounded-lg border border-gray-300 px-4 py-2 focus:ring-2 focus:ring-green-500 focus:border-transparent outline-none transition"
                required
              >
                <option value="M">Monthly</option>
                <option value="Q">Quarterly</option>
                <option value="H">Half Yearly</option>
                <option value="Y">Yearly</option>
                <option value="O">One Time</option>
              </select>
            </div>
          </div>

          {/* Remarks */}
          <div>
            <label className="block text-sm font-semibold text-gray-700 mb-1">
              Remarks (Optional)
            </label>
            <textarea
              name="remarks"
              value={form.remarks}
              placeholder="Enter any additional notes..."
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
            {loading ? 'Saving...' : initialData ? 'Update Sale' : 'Save Sale'}
          </button>
        </div>
      </div>
    </div>
  );
}