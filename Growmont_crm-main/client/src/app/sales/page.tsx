// "use client";

// import React, { useEffect, useState } from "react";
// import Sidebar from "@/components/Sidebar";
// import Navbar from "@/components/Navbar";
// import toast from "react-hot-toast";
// import { api, endpoints } from "@/utils/api";
// import AddSalesModal from "@/components/AddSalesModal";

// interface Sale {
//   id: number;
//   date: string;
//   client_name: string;
//   sales_rep: number;
//   sales_rep_name: string;
//   product: string;
//   product_display: string;
//   company: string;
//   scheme: string;
//   amount: string;
//   frequency: string;
//   frequency_display: string;
//   remarks: string;
// }

// const SalesPage = () => {
//   const [sales, setSales] = useState<Sale[]>([]);
//   const [filteredSales, setFilteredSales] = useState<Sale[]>([]);
//   const [showModal, setShowModal] = useState(false);
//   const [loading, setLoading] = useState(true);
//   const [selectedProduct, setSelectedProduct] = useState<string>("ALL");
//   const [editingSale, setEditingSale] = useState<any>(null);

//   const productCategories = [
//     { id: "ALL", name: "All Products" },
//     { id: "MF", name: "Mutual Funds" },
//     { id: "HI", name: "Health Insurance" },
//     { id: "GI", name: "General Insurance" },
//     { id: "LI", name: "Life Insurance" },
//     { id: "NCD", name: "NCDs" },
//     { id: "MLD", name: "MLDs" },
//     { id: "BOND", name: "Bonds" },
//     { id: "CFD", name: "Corporate FDs" },
//     { id: "AIF", name: "AIFs" },
//     { id: "PMS", name: "PMS" },
//   ];

//   useEffect(() => {
//     fetchSales();
//   }, []);

//   useEffect(() => {
//     filterSales();
//   }, [sales, selectedProduct]);

//   const fetchSales = async () => {
//     try {
//       setLoading(true);
//       const data = await api.get(endpoints.sales);
//       console.log('Sales loaded:', data);
//       setSales(data);
//       toast.success(`Loaded ${data.length} sales`);
//     } catch (error) {
//       console.error('Failed to load sales:', error);
//       toast.error("Failed to load sales");
//     } finally {
//       setLoading(false);
//     }
//   };

//   const filterSales = () => {
//     if (selectedProduct === "ALL") {
//       setFilteredSales(sales);
//     } else {
//       setFilteredSales(sales.filter(s => s.product === selectedProduct));
//     }
//   };

//   const handleEdit = (sale: Sale) => {
//     setEditingSale({
//       id: sale.id,
//       date: sale.date,
//       client_name: sale.client_name,
//       sales_rep: sale.sales_rep,
//       product: sale.product,
//       company: sale.company,
//       scheme: sale.scheme,
//       amount: sale.amount,
//       frequency: sale.frequency,
//       remarks: sale.remarks,
//     });
//     setShowModal(true);
//   };

//   const handleDelete = async (id: number) => {
//     if (!confirm('Are you sure you want to delete this sale?')) {
//       return;
//     }

//     try {
//       await api.delete(endpoints.deleteSale(id));
//       toast.success('Sale deleted successfully');
//       fetchSales();
//     } catch (error) {
//       console.error('Failed to delete sale:', error);
//       toast.error('Failed to delete sale');
//     }
//   };

//   const handleSaveSale = () => {
//     setShowModal(false);
//     setEditingSale(null);
//     fetchSales();
//   };

//   const handleCloseModal = () => {
//     setShowModal(false);
//     setEditingSale(null);
//   };

//   const formatAmount = (amount: string) => {
//     return new Intl.NumberFormat('en-IN', {
//       style: 'currency',
//       currency: 'INR',
//       maximumFractionDigits: 0,
//     }).format(parseFloat(amount));
//   };

//   const formatDate = (dateString: string) => {
//     const date = new Date(dateString);
//     return date.toLocaleDateString('en-IN', { 
//       day: '2-digit', 
//       month: 'short', 
//       year: 'numeric' 
//     });
//   };

//   const getProductBadgeColor = (product: string) => {
//     const colors: { [key: string]: string } = {
//       'MF': 'bg-blue-100 text-blue-700 border-blue-200',
//       'HI': 'bg-green-100 text-green-700 border-green-200',
//       'GI': 'bg-purple-100 text-purple-700 border-purple-200',
//       'LI': 'bg-indigo-100 text-indigo-700 border-indigo-200',
//       'NCD': 'bg-yellow-100 text-yellow-700 border-yellow-200',
//       'MLD': 'bg-pink-100 text-pink-700 border-pink-200',
//       'BOND': 'bg-orange-100 text-orange-700 border-orange-200',
//       'CFD': 'bg-teal-100 text-teal-700 border-teal-200',
//       'AIF': 'bg-cyan-100 text-cyan-700 border-cyan-200',
//       'PMS': 'bg-violet-100 text-violet-700 border-violet-200',
//     };
//     return colors[product] || 'bg-gray-100 text-gray-700 border-gray-200';
//   };

//   return (
//     <div className="min-h-screen bg-[#F4F9FD]">
//       <Sidebar />
//       <Navbar />

//       <div className="flex-1 flex flex-col overflow-hidden ml-64 mt-16 p-6">
//         <main className="flex-1 overflow-y-auto">
//           <div className="flex justify-between items-center mb-6">
//             <h1 className="text-3xl font-bold text-[#00337C]">Sales</h1>

//             <button
//               onClick={() => setShowModal(true)}
//               className="bg-[#2D8A4E] hover:bg-[#236b3d] transition-colors text-white px-4 py-2 rounded-lg flex items-center gap-2 cursor-pointer font-medium"
//             >
//               <span className="text-lg">+</span>
//               Add Sale
//             </button>
//           </div>

//           <div className="grid grid-cols-12 gap-6">
//             {/* Left Panel - Product Filter */}
//             <div className="col-span-3">
//               <div className="bg-white rounded-lg shadow-sm p-4">
//                 <h2 className="font-semibold text-gray-900 mb-4">
//                   Filter by Product
//                 </h2>

//                 <div className="space-y-2">
//                   {productCategories.map((category) => (
//                     <div
//                       key={category.id}
//                       onClick={() => setSelectedProduct(category.id)}
//                       className={`cursor-pointer p-3 rounded-lg transition ${
//                         selectedProduct === category.id
//                           ? "bg-[#00337C]/11 border-l-4 border-[#00337C]"
//                           : "hover:bg-gray-50"
//                       }`}
//                     >
//                       <p className="font-medium text-gray-900">
//                         {category.name}
//                       </p>
//                       <p className="text-xs text-gray-500 mt-1">
//                         {category.id === 'ALL' 
//                           ? sales.length 
//                           : sales.filter(s => s.product === category.id).length
//                         } sales
//                       </p>
//                     </div>
//                   ))}
//                 </div>
//               </div>
//             </div>

//             {/* Right Panel - Sales List */}
//             <div className="col-span-9">
//               <div className="bg-white rounded-lg shadow-sm p-6">
//                 <div className="flex justify-between items-center mb-6">
//                   <h2 className="text-xl font-semibold text-gray-900">
//                     Sales Overview
//                   </h2>
//                   <span className="text-sm text-gray-500">
//                     Showing {filteredSales.length} of {sales.length} sales
//                   </span>
//                 </div>

//                 {loading ? (
//                   <div className="text-center py-12">
//                     <div className="inline-block animate-spin rounded-full h-10 w-10 border-b-2 border-[#00337C]"></div>
//                     <p className="mt-4 text-gray-600">Loading sales...</p>
//                   </div>
//                 ) : filteredSales.length === 0 ? (
//                   <div className="text-center py-12">
//                     <svg className="mx-auto h-12 w-12 text-gray-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
//                       <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 8c-1.657 0-3 .895-3 2s1.343 2 3 2 3 .895 3 2-1.343 2-3 2m0-8c1.11 0 2.08.402 2.599 1M12 8V7m0 1v8m0 0v1m0-1c-1.11 0-2.08-.402-2.599-1M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
//                     </svg>
//                     <p className="mt-4 text-gray-500">No sales found</p>
//                     <button
//                       onClick={() => setShowModal(true)}
//                       className="mt-4 text-[#2D8A4E] hover:underline font-medium"
//                     >
//                       Add your first sale
//                     </button>
//                   </div>
//                 ) : (
//                   <div className="space-y-3">
//                     {filteredSales.map((sale) => (
//                       <div
//                         key={sale.id}
//                         className="bg-[#F4F9FD] p-4 rounded-lg hover:shadow-md transition border border-gray-100"
//                       >
//                         <div className="flex items-start justify-between">
//                           <div className="flex-1 grid grid-cols-6 gap-4">
                            
//                             {/* Date */}
//                             <div>
//                               <p className="text-xs text-gray-500 mb-1">Date</p>
//                               <p className="text-sm font-medium text-gray-900">
//                                 {formatDate(sale.date)}
//                               </p>
//                             </div>

//                             {/* Client */}
//                             <div>
//                               <p className="text-xs text-gray-500 mb-1">Client</p>
//                               <p className="text-sm font-medium text-gray-900">
//                                 {sale.client_name}
//                               </p>
//                             </div>

//                             {/* Product */}
//                             <div>
//                               <p className="text-xs text-gray-500 mb-1">Product</p>
//                               <span className={`inline-flex px-2 py-1 rounded-full text-xs font-semibold border ${getProductBadgeColor(sale.product)}`}>
//                                 {sale.product_display}
//                               </span>
//                             </div>

//                             {/* Amount */}
//                             <div>
//                               <p className="text-xs text-gray-500 mb-1">Amount</p>
//                               <p className="text-sm font-bold text-gray-900">
//                                 {formatAmount(sale.amount)}
//                               </p>
//                             </div>

//                             {/* Frequency */}
//                             <div>
//                               <p className="text-xs text-gray-500 mb-1">Frequency</p>
//                               <p className="text-sm text-gray-700">
//                                 {sale.frequency_display}
//                               </p>
//                             </div>

//                             {/* Sales Rep */}
//                             <div>
//                               <p className="text-xs text-gray-500 mb-1">Sales Rep</p>
//                               <p className="text-sm font-medium text-gray-900">
//                                 {sale.sales_rep_name}
//                               </p>
//                             </div>

//                           </div>

//                           {/* Action Buttons */}
//                           <div className="flex items-center gap-2 ml-4">
//                             <button
//                               onClick={() => handleEdit(sale)}
//                               className="p-2 text-blue-600 hover:bg-blue-50 rounded-lg transition"
//                               title="Edit"
//                             >
//                               <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
//                                 <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z" />
//                               </svg>
//                             </button>
//                             <button
//                               onClick={() => handleDelete(sale.id)}
//                               className="p-2 text-red-600 hover:bg-red-50 rounded-lg transition"
//                               title="Delete"
//                             >
//                               <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
//                                 <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
//                               </svg>
//                             </button>
//                           </div>
//                         </div>

//                         {/* Company, Scheme, Remarks (Second Row) */}
//                         <div className="mt-3 pt-3 border-t border-gray-200 grid grid-cols-3 gap-4">
//                           <div>
//                             <p className="text-xs text-gray-500 mb-1">Company</p>
//                             <p className="text-sm text-gray-700">{sale.company}</p>
//                           </div>
//                           <div>
//                             <p className="text-xs text-gray-500 mb-1">Scheme</p>
//                             <p className="text-sm text-gray-700">{sale.scheme}</p>
//                           </div>
//                           {sale.remarks && (
//                             <div>
//                               <p className="text-xs text-gray-500 mb-1">Remarks</p>
//                               <p className="text-sm text-gray-700 truncate">{sale.remarks}</p>
//                             </div>
//                           )}
//                         </div>
//                       </div>
//                     ))}
//                   </div>
//                 )}
//               </div>
//             </div>
//           </div>
//         </main>
//       </div>

//       {/* Modal */}
//       <AddSalesModal
//         isOpen={showModal}
//         onClose={handleCloseModal}
//         onSave={handleSaveSale}
//         initialData={editingSale}
//       />
//     </div>
//   );
// };

// export default SalesPage;

"use client";

import React, { useEffect, useState } from "react";
import Sidebar from "@/components/Sidebar";
import Navbar from "@/components/Navbar";
import toast from "react-hot-toast";
import { api, endpoints } from "@/utils/api";
import AddSalesModal from "@/components/AddSalesModal";

interface Sale {
  id: number;
  date: string;
  client_name: string;
  sales_rep: number;
  sales_rep_name: string;
  product: string;
  product_display: string;
  company: string;
  scheme: string;
  amount: string;
  frequency: string;
  frequency_display: string;
  remarks: string;
}

const SalesPage = () => {
  const [sales, setSales] = useState<Sale[]>([]);
  const [filteredSales, setFilteredSales] = useState<Sale[]>([]);
  const [showModal, setShowModal] = useState(false);
  const [loading, setLoading] = useState(true);
  const [selectedProduct, setSelectedProduct] = useState<string>("ALL");
  const [editingSale, setEditingSale] = useState<any>(null);
  const [showFilterDrawer, setShowFilterDrawer] = useState(false);

  const productCategories = [
    { id: "ALL", name: "All Products" },
    { id: "MF", name: "Mutual Funds" },
    { id: "HI", name: "Health Insurance" },
    { id: "GI", name: "General Insurance" },
    { id: "LI", name: "Life Insurance" },
    { id: "NCD", name: "NCDs" },
    { id: "MLD", name: "MLDs" },
    { id: "BOND", name: "Bonds" },
    { id: "CFD", name: "Corporate FDs" },
    { id: "AIF", name: "AIFs" },
    { id: "PMS", name: "PMS" },
  ];

  useEffect(() => {
    fetchSales();
  }, []);

  useEffect(() => {
    filterSales();
  }, [sales, selectedProduct]);

  const fetchSales = async () => {
    try {
      setLoading(true);
      const data = await api.get(endpoints.sales);
      setSales(data);
      toast.success(`Loaded ${data.length} sales`);
    } catch (error) {
      toast.error("Failed to load sales");
    } finally {
      setLoading(false);
    }
  };

  const filterSales = () => {
    if (selectedProduct === "ALL") {
      setFilteredSales(sales);
    } else {
      setFilteredSales(sales.filter((s) => s.product === selectedProduct));
    }
  };

  const handleEdit = (sale: Sale) => {
    setEditingSale({
      id: sale.id,
      date: sale.date,
      client_name: sale.client_name,
      sales_rep: sale.sales_rep,
      product: sale.product,
      company: sale.company,
      scheme: sale.scheme,
      amount: sale.amount,
      frequency: sale.frequency,
      remarks: sale.remarks,
    });
    setShowModal(true);
  };

  const handleDelete = async (id: number) => {
    if (!confirm("Are you sure you want to delete this sale?")) return;
    try {
      await api.delete(endpoints.deleteSale(id));
      toast.success("Sale deleted successfully");
      fetchSales();
    } catch (error) {
      toast.error("Failed to delete sale");
    }
  };

  const handleSaveSale = () => {
    setShowModal(false);
    setEditingSale(null);
    fetchSales();
  };

  const handleCloseModal = () => {
    setShowModal(false);
    setEditingSale(null);
  };

  const formatAmount = (amount: string) => {
    return new Intl.NumberFormat("en-IN", {
      style: "currency",
      currency: "INR",
      maximumFractionDigits: 0,
    }).format(parseFloat(amount));
  };

  const formatDate = (dateString: string) => {
    const date = new Date(dateString);
    return date.toLocaleDateString("en-IN", {
      day: "2-digit",
      month: "short",
      year: "numeric",
    });
  };

  const getProductBadgeColor = (product: string) => {
    const colors: { [key: string]: string } = {
      MF: "bg-blue-100 text-blue-700 border-blue-200",
      HI: "bg-green-100 text-green-700 border-green-200",
      GI: "bg-purple-100 text-purple-700 border-purple-200",
      LI: "bg-indigo-100 text-indigo-700 border-indigo-200",
      NCD: "bg-yellow-100 text-yellow-700 border-yellow-200",
      MLD: "bg-pink-100 text-pink-700 border-pink-200",
      BOND: "bg-orange-100 text-orange-700 border-orange-200",
      CFD: "bg-teal-100 text-teal-700 border-teal-200",
      AIF: "bg-cyan-100 text-cyan-700 border-cyan-200",
      PMS: "bg-violet-100 text-violet-700 border-violet-200",
    };
    return colors[product] || "bg-gray-100 text-gray-700 border-gray-200";
  };

  const FilterPanel = () => (
    <div className="bg-white rounded-lg shadow-sm p-4">
      <h2 className="font-semibold text-gray-900 mb-4">Filter by Product</h2>
      <div className="space-y-2">
        {productCategories.map((category) => (
          <div
            key={category.id}
            onClick={() => {
              setSelectedProduct(category.id);
              setShowFilterDrawer(false);
            }}
            className={`cursor-pointer p-3 rounded-lg transition ${
              selectedProduct === category.id
                ? "bg-[#00337C]/11 border-l-4 border-[#00337C]"
                : "hover:bg-gray-50"
            }`}
          >
            <p className="font-medium text-gray-900">{category.name}</p>
            <p className="text-xs text-gray-500 mt-1">
              {category.id === "ALL"
                ? sales.length
                : sales.filter((s) => s.product === category.id).length}{" "}
              sales
            </p>
          </div>
        ))}
      </div>
    </div>
  );

  return (
    <div className="min-h-screen bg-[#F4F9FD]">
      <Sidebar />
      <Navbar />

      {/* Mobile Filter Drawer */}
      {showFilterDrawer && (
        <div className="md:hidden fixed inset-0 z-50 flex">
          <div
            className="fixed inset-0 bg-black/40"
            onClick={() => setShowFilterDrawer(false)}
          />
          <div className="relative z-50 w-72 bg-white h-full flex flex-col shadow-xl overflow-y-auto p-4">
            <div className="flex items-center justify-between mb-4">
              <h2 className="font-semibold text-gray-900 text-lg">Filter</h2>
              <button
                onClick={() => setShowFilterDrawer(false)}
                className="p-2 rounded-lg hover:bg-gray-100"
              >
                <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
                </svg>
              </button>
            </div>
            <FilterPanel />
          </div>
        </div>
      )}

      <div className="md:ml-64 mt-[4rem] md:mt-16 p-4 md:p-6">
        <main>
          {/* Header */}
          <div className="flex justify-between items-center mb-6 gap-3">
            <h1 className="text-2xl md:text-3xl font-bold text-[#00337C]">Sales</h1>
            <div className="flex items-center gap-2">
              {/* Mobile filter button */}
              <button
                onClick={() => setShowFilterDrawer(true)}
                className="md:hidden flex items-center gap-2 border border-gray-300 bg-white text-gray-700 px-3 py-2 rounded-lg font-medium text-sm"
              >
                <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M3 4a1 1 0 011-1h16a1 1 0 011 1v2a1 1 0 01-.293.707L13 13.414V19a1 1 0 01-.553.894l-4 2A1 1 0 017 21v-7.586L3.293 6.707A1 1 0 013 6V4z" />
                </svg>
                {selectedProduct !== "ALL" ? (
                  <span className="text-[#00337C] font-semibold">
                    {productCategories.find((c) => c.id === selectedProduct)?.name}
                  </span>
                ) : (
                  "Filter"
                )}
              </button>

              <button
                onClick={() => setShowModal(true)}
                className="bg-[#2D8A4E] hover:bg-[#236b3d] transition-colors text-white px-4 py-2 rounded-lg flex items-center gap-2 cursor-pointer font-medium text-sm md:text-base"
              >
                <span className="text-lg">+</span>
                <span>Add Sale</span>
              </button>
            </div>
          </div>

          {/* Body */}
          <div className="flex gap-6">
            {/* Left Panel - desktop only */}
            <div className="hidden md:block w-64 shrink-0">
              <FilterPanel />
            </div>

            {/* Right Panel - Sales List */}
            <div className="flex-1 min-w-0">
              <div className="bg-white rounded-lg shadow-sm p-4 md:p-6">
                <div className="flex justify-between items-center mb-4 md:mb-6">
                  <h2 className="text-lg md:text-xl font-semibold text-gray-900">
                    Sales Overview
                  </h2>
                  <span className="text-xs md:text-sm text-gray-500">
                    {filteredSales.length} of {sales.length}
                  </span>
                </div>

                {loading ? (
                  <div className="text-center py-12">
                    <div className="inline-block animate-spin rounded-full h-10 w-10 border-b-2 border-[#00337C]"></div>
                    <p className="mt-4 text-gray-600">Loading sales...</p>
                  </div>
                ) : filteredSales.length === 0 ? (
                  <div className="text-center py-12">
                    <svg className="mx-auto h-12 w-12 text-gray-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 8c-1.657 0-3 .895-3 2s1.343 2 3 2 3 .895 3 2-1.343 2-3 2m0-8c1.11 0 2.08.402 2.599 1M12 8V7m0 1v8m0 0v1m0-1c-1.11 0-2.08-.402-2.599-1M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
                    </svg>
                    <p className="mt-4 text-gray-500">No sales found</p>
                    <button
                      onClick={() => setShowModal(true)}
                      className="mt-4 text-[#2D8A4E] hover:underline font-medium"
                    >
                      Add your first sale
                    </button>
                  </div>
                ) : (
                  <div className="space-y-3">
                    {filteredSales.map((sale) => (
                      <div
                        key={sale.id}
                        className="bg-[#F4F9FD] p-3 md:p-4 rounded-lg hover:shadow-md transition border border-gray-100"
                      >
                        {/* Top row */}
                        <div className="flex items-start justify-between gap-2">
                          <div className="flex-1 min-w-0">
                            {/* Mobile: stacked layout */}
                            <div className="grid grid-cols-2 gap-x-4 gap-y-2 md:hidden">
                              <div>
                                <p className="text-xs text-gray-500">Date</p>
                                <p className="text-sm font-medium text-gray-900">{formatDate(sale.date)}</p>
                              </div>
                              <div>
                                <p className="text-xs text-gray-500">Client</p>
                                <p className="text-sm font-medium text-gray-900 truncate">{sale.client_name}</p>
                              </div>
                              <div>
                                <p className="text-xs text-gray-500">Product</p>
                                <span className={`inline-flex px-2 py-0.5 rounded-full text-xs font-semibold border ${getProductBadgeColor(sale.product)}`}>
                                  {sale.product_display}
                                </span>
                              </div>
                              <div>
                                <p className="text-xs text-gray-500">Amount</p>
                                <p className="text-sm font-bold text-gray-900">{formatAmount(sale.amount)}</p>
                              </div>
                              <div>
                                <p className="text-xs text-gray-500">Frequency</p>
                                <p className="text-sm text-gray-700">{sale.frequency_display}</p>
                              </div>
                              <div>
                                <p className="text-xs text-gray-500">Sales Rep</p>
                                <p className="text-sm font-medium text-gray-900 truncate">{sale.sales_rep_name}</p>
                              </div>
                            </div>

                            {/* Desktop: 6-col grid */}
                            <div className="hidden md:grid grid-cols-6 gap-4">
                              <div>
                                <p className="text-xs text-gray-500 mb-1">Date</p>
                                <p className="text-sm font-medium text-gray-900">{formatDate(sale.date)}</p>
                              </div>
                              <div>
                                <p className="text-xs text-gray-500 mb-1">Client</p>
                                <p className="text-sm font-medium text-gray-900">{sale.client_name}</p>
                              </div>
                              <div>
                                <p className="text-xs text-gray-500 mb-1">Product</p>
                                <span className={`inline-flex px-2 py-1 rounded-full text-xs font-semibold border ${getProductBadgeColor(sale.product)}`}>
                                  {sale.product_display}
                                </span>
                              </div>
                              <div>
                                <p className="text-xs text-gray-500 mb-1">Amount</p>
                                <p className="text-sm font-bold text-gray-900">{formatAmount(sale.amount)}</p>
                              </div>
                              <div>
                                <p className="text-xs text-gray-500 mb-1">Frequency</p>
                                <p className="text-sm text-gray-700">{sale.frequency_display}</p>
                              </div>
                              <div>
                                <p className="text-xs text-gray-500 mb-1">Sales Rep</p>
                                <p className="text-sm font-medium text-gray-900">{sale.sales_rep_name}</p>
                              </div>
                            </div>
                          </div>

                          {/* Action Buttons */}
                          <div className="flex items-center gap-1 shrink-0">
                            <button
                              onClick={() => handleEdit(sale)}
                              className="p-2 text-blue-600 hover:bg-blue-50 rounded-lg transition"
                              title="Edit"
                            >
                              <svg className="w-4 h-4 md:w-5 md:h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z" />
                              </svg>
                            </button>
                            <button
                              onClick={() => handleDelete(sale.id)}
                              className="p-2 text-red-600 hover:bg-red-50 rounded-lg transition"
                              title="Delete"
                            >
                              <svg className="w-4 h-4 md:w-5 md:h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
                              </svg>
                            </button>
                          </div>
                        </div>

                        {/* Bottom row - Company, Scheme, Remarks */}
                        <div className="mt-3 pt-3 border-t border-gray-200 grid grid-cols-2 md:grid-cols-3 gap-3 md:gap-4">
                          <div>
                            <p className="text-xs text-gray-500 mb-1">Company</p>
                            <p className="text-sm text-gray-700">{sale.company}</p>
                          </div>
                          <div>
                            <p className="text-xs text-gray-500 mb-1">Scheme</p>
                            <p className="text-sm text-gray-700">{sale.scheme}</p>
                          </div>
                          {sale.remarks && (
                            <div className="col-span-2 md:col-span-1">
                              <p className="text-xs text-gray-500 mb-1">Remarks</p>
                              <p className="text-sm text-gray-700 truncate">{sale.remarks}</p>
                            </div>
                          )}
                        </div>
                      </div>
                    ))}
                  </div>
                )}
              </div>
            </div>
          </div>
        </main>
      </div>

      <AddSalesModal
        isOpen={showModal}
        onClose={handleCloseModal}
        onSave={handleSaveSale}
        initialData={editingSale}
      />
    </div>
  );
};

export default SalesPage;