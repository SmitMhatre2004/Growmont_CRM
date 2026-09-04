// "use client";

// import React, { useEffect, useState } from "react";
// import Sidebar from "@/components/Sidebar";
// import Navbar from "@/components/Navbar";
// import toast from "react-hot-toast";
// import AddInteractionModal from "@/components/AddInteractionsModal";
// import { api, endpoints } from "@/utils/api";

// interface Interaction {
//   id: number;
//   date: string;
//   client_name: string;
//   client_contact: string;
//   employee: number;
//   employee_name: string;
//   follow_up_date: string;
//   follow_up_time: string;
//   priority: string;
//   priority_display: string;
//   discussion_notes: string;
// }

// const InteractionsPage = () => {
//   const [interactions, setInteractions] = useState<Interaction[]>([]);
//   const [filteredInteractions, setFilteredInteractions] = useState<Interaction[]>([]);
//   const [showModal, setShowModal] = useState(false);
//   const [loading, setLoading] = useState(true);
//   const [selectedPriority, setSelectedPriority] = useState<string>("ALL");
//   const [editingInteraction, setEditingInteraction] = useState<any>(null);

//   useEffect(() => {
//     fetchInteractions();
//   }, []);

//   useEffect(() => {
//     filterInteractions();
//   }, [interactions, selectedPriority]);

//   const fetchInteractions = async () => {
//     try {
//       setLoading(true);
//       const data = await api.get(endpoints.interactions);
//       console.log('Interactions loaded:', data);
//       setInteractions(data);
//       toast.success(`Loaded ${data.length} interactions`);
//     } catch (error) {
//       console.error('Failed to load interactions:', error);
//       toast.error("Failed to load interactions");
//     } finally {
//       setLoading(false);
//     }
//   };

//   const filterInteractions = () => {
//     if (selectedPriority === "ALL") {
//       setFilteredInteractions(interactions);
//     } else {
//       setFilteredInteractions(
//         interactions.filter(i => i.priority === selectedPriority)
//       );
//     }
//   };

//   const handleEdit = (interaction: Interaction) => {
//     setEditingInteraction({
//       id: interaction.id,
//       date: interaction.date,
//       client_name: interaction.client_name,
//       client_contact: interaction.client_contact,
//       employee: interaction.employee,
//       follow_up_date: interaction.follow_up_date,
//       follow_up_time: interaction.follow_up_time,
//       priority: interaction.priority,
//       discussion_notes: interaction.discussion_notes,
//     });
//     setShowModal(true);
//   };

//   const handleDelete = async (id: number) => {
//     if (!confirm('Are you sure you want to delete this interaction?')) {
//       return;
//     }

//     try {
//       await api.delete(endpoints.deleteInteraction(id));
//       toast.success('Interaction deleted successfully');
//       fetchInteractions();
//     } catch (error) {
//       console.error('Failed to delete interaction:', error);
//       toast.error('Failed to delete interaction');
//     }
//   };

//   const handleSaveInteraction = () => {
//     setShowModal(false);
//     setEditingInteraction(null);
//     fetchInteractions();
//   };

//   const handleCloseModal = () => {
//     setShowModal(false);
//     setEditingInteraction(null);
//   };

//   const getPriorityColor = (priority: string) => {
//     switch (priority) {
//       case "HIGH":
//         return "text-red-600 bg-red-50";
//       case "MEDIUM":
//         return "text-yellow-600 bg-yellow-50";
//       case "LOW":
//         return "text-green-600 bg-green-50";
//       default:
//         return "text-gray-600 bg-gray-50";
//     }
//   };

//   const getPriorityBadgeColor = (priority: string) => {
//     switch (priority) {
//       case "HIGH":
//         return "bg-red-100 text-red-700 border-red-200";
//       case "MEDIUM":
//         return "bg-yellow-100 text-yellow-700 border-yellow-200";
//       case "LOW":
//         return "bg-green-100 text-green-700 border-green-200";
//       default:
//         return "bg-gray-100 text-gray-700 border-gray-200";
//     }
//   };

//   const formatDate = (dateString: string) => {
//     const date = new Date(dateString);
//     return date.toLocaleDateString('en-IN', { 
//       day: '2-digit', 
//       month: 'short', 
//       year: 'numeric' 
//     });
//   };

//   const formatTime = (timeString: string) => {
//     if (!timeString) return '';
//     const [hours, minutes] = timeString.split(':');
//     const hour = parseInt(hours);
//     const ampm = hour >= 12 ? 'PM' : 'AM';
//     const displayHour = hour % 12 || 12;
//     return `${displayHour}:${minutes} ${ampm}`;
//   };

//   return (
//     <div className="min-h-screen bg-[#F4F9FD]">
//       <Sidebar />
//       <Navbar />

//       <div className="flex-1 flex flex-col overflow-hidden ml-64 mt-16 p-6">
//         <main className="flex-1 overflow-y-auto">
//           <div className="flex justify-between items-center mb-6">
//             <h1 className="text-3xl font-bold text-[#00337C]">Interactions</h1>

//             <button
//               onClick={() => setShowModal(true)}
//               className="bg-[#2D8A4E] hover:bg-[#236b3d] transition-colors text-white px-4 py-2 rounded-lg flex items-center gap-2 cursor-pointer font-medium"
//             >
//               <span className="text-lg">+</span>
//               Add Interaction
//             </button>
//           </div>

//           <div className="grid grid-cols-12 gap-6">
//             {/* Left Panel - Priority Filter */}
//             <div className="col-span-3">
//               <div className="bg-white rounded-lg shadow-sm p-4">
//                 <h2 className="font-semibold text-gray-900 mb-4">
//                   Filter by Priority
//                 </h2>

//                 <div className="space-y-2">
//                   {['ALL', 'HIGH', 'MEDIUM', 'LOW'].map((priority) => (
//                     <div
//                       key={priority}
//                       onClick={() => setSelectedPriority(priority)}
//                       className={`cursor-pointer p-3 rounded-lg transition ${
//                         selectedPriority === priority
//                           ? "bg-[#00337C]/11 border-l-4 border-[#00337C]"
//                           : "hover:bg-gray-50"
//                       }`}
//                     >
//                       <p className="font-medium text-gray-900">
//                         {priority === 'ALL' ? 'All Interactions' : `${priority} Priority`}
//                       </p>
//                       <p className="text-xs text-gray-500 mt-1">
//                         {priority === 'ALL' 
//                           ? interactions.length 
//                           : interactions.filter(i => i.priority === priority).length
//                         } items
//                       </p>
//                     </div>
//                   ))}
//                 </div>
//               </div>
//             </div>

//             {/* Right Panel - Interactions List */}
//             <div className="col-span-9">
//               <div className="bg-white rounded-lg shadow-sm p-6">
//                 <div className="flex justify-between items-center mb-6">
//                   <h2 className="text-xl font-semibold text-gray-900">
//                     Interactions Overview
//                   </h2>
//                   <span className="text-sm text-gray-500">
//                     Showing {filteredInteractions.length} of {interactions.length} interactions
//                   </span>
//                 </div>

//                 {loading ? (
//                   <div className="text-center py-12">
//                     <div className="inline-block animate-spin rounded-full h-10 w-10 border-b-2 border-[#00337C]"></div>
//                     <p className="mt-4 text-gray-600">Loading interactions...</p>
//                   </div>
//                 ) : filteredInteractions.length === 0 ? (
//                   <div className="text-center py-12">
//                     <svg className="mx-auto h-12 w-12 text-gray-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
//                       <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M20 13V6a2 2 0 00-2-2H6a2 2 0 00-2 2v7m16 0v5a2 2 0 01-2 2H6a2 2 0 01-2-2v-5m16 0h-2.586a1 1 0 00-.707.293l-2.414 2.414a1 1 0 01-.707.293h-3.172a1 1 0 01-.707-.293l-2.414-2.414A1 1 0 006.586 13H4" />
//                     </svg>
//                     <p className="mt-4 text-gray-500">No interactions found</p>
//                     <button
//                       onClick={() => setShowModal(true)}
//                       className="mt-4 text-[#2D8A4E] hover:underline font-medium"
//                     >
//                       Add your first interaction
//                     </button>
//                   </div>
//                 ) : (
//                   <div className="space-y-3">
//                     {filteredInteractions.map((interaction) => (
//                       <div
//                         key={interaction.id}
//                         className="bg-[#F4F9FD] p-4 rounded-lg hover:shadow-md transition border border-gray-100"
//                       >
//                         <div className="flex items-start justify-between">
//                           <div className="flex-1 grid grid-cols-5 gap-4">
                            
//                             {/* Date */}
//                             <div>
//                               <p className="text-xs text-gray-500 mb-1">Date</p>
//                               <p className="text-sm font-medium text-gray-900">
//                                 {formatDate(interaction.date)}
//                               </p>
//                             </div>

//                             {/* Client Info */}
//                             <div>
//                               <p className="text-xs text-gray-500 mb-1">Client</p>
//                               <p className="text-sm font-medium text-gray-900">
//                                 {interaction.client_name}
//                               </p>
//                               <p className="text-xs text-gray-500">
//                                 {interaction.client_contact}
//                               </p>
//                             </div>

//                             {/* Representative */}
//                             <div>
//                               <p className="text-xs text-gray-500 mb-1">Representative</p>
//                               <p className="text-sm font-medium text-gray-900">
//                                 {interaction.employee_name}
//                               </p>
//                             </div>

//                             {/* Follow-up */}
//                             <div>
//                               <p className="text-xs text-gray-500 mb-1">Follow-up</p>
//                               <p className="text-sm font-medium text-gray-900">
//                                 {formatDate(interaction.follow_up_date)}
//                               </p>
//                               <p className="text-xs text-gray-600">
//                                 {formatTime(interaction.follow_up_time)}
//                               </p>
//                             </div>

//                             {/* Priority */}
//                             <div>
//                               <p className="text-xs text-gray-500 mb-1">Priority</p>
//                               <span className={`inline-flex px-3 py-1 rounded-full text-xs font-semibold border ${getPriorityBadgeColor(interaction.priority)}`}>
//                                 {interaction.priority_display}
//                               </span>
//                             </div>

//                           </div>

//                           {/* Action Buttons */}
//                           <div className="flex items-center gap-2 ml-4">
//                             <button
//                               onClick={() => handleEdit(interaction)}
//                               className="p-2 text-blue-600 hover:bg-blue-50 rounded-lg transition"
//                               title="Edit"
//                             >
//                               <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
//                                 <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z" />
//                               </svg>
//                             </button>
//                             <button
//                               onClick={() => handleDelete(interaction.id)}
//                               className="p-2 text-red-600 hover:bg-red-50 rounded-lg transition"
//                               title="Delete"
//                             >
//                               <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
//                                 <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
//                               </svg>
//                             </button>
//                           </div>
//                         </div>

//                         {/* Discussion Notes (if present) */}
//                         {interaction.discussion_notes && (
//                           <div className="mt-3 pt-3 border-t border-gray-200">
//                             <p className="text-xs text-gray-500 mb-1">Notes</p>
//                             <p className="text-sm text-gray-700">
//                               {interaction.discussion_notes}
//                             </p>
//                           </div>
//                         )}
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
//       <AddInteractionModal
//         isOpen={showModal}
//         onClose={handleCloseModal}
//         onSave={handleSaveInteraction}
//         initialData={editingInteraction}
//       />
//     </div>
//   );
// };

// export default InteractionsPage;

"use client";

import React, { useEffect, useState } from "react";
import Sidebar from "@/components/Sidebar";
import Navbar from "@/components/Navbar";
import toast from "react-hot-toast";
import AddInteractionModal from "@/components/AddInteractionsModal";
import { api, endpoints } from "@/utils/api";

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

const InteractionsPage = () => {
  const [interactions, setInteractions] = useState<Interaction[]>([]);
  const [filteredInteractions, setFilteredInteractions] = useState<Interaction[]>([]);
  const [showModal, setShowModal] = useState(false);
  const [loading, setLoading] = useState(true);
  const [selectedPriority, setSelectedPriority] = useState<string>("ALL");
  const [editingInteraction, setEditingInteraction] = useState<any>(null);
  const [showFilterDrawer, setShowFilterDrawer] = useState(false);

  useEffect(() => {
    fetchInteractions();
  }, []);

  useEffect(() => {
    filterInteractions();
  }, [interactions, selectedPriority]);

  const fetchInteractions = async () => {
    try {
      setLoading(true);
      const data = await api.get(endpoints.interactions);
      console.log('Interactions loaded:', data);
      setInteractions(data);
      toast.success(`Loaded ${data.length} interactions`);
    } catch (error) {
      console.error('Failed to load interactions:', error);
      toast.error("Failed to load interactions");
    } finally {
      setLoading(false);
    }
  };

  const filterInteractions = () => {
    if (selectedPriority === "ALL") {
      setFilteredInteractions(interactions);
    } else {
      setFilteredInteractions(
        interactions.filter(i => i.priority === selectedPriority)
      );
    }
  };

  const handleEdit = (interaction: Interaction) => {
    setEditingInteraction({
      id: interaction.id,
      date: interaction.date,
      client_name: interaction.client_name,
      client_contact: interaction.client_contact,
      employee: interaction.employee,
      follow_up_date: interaction.follow_up_date,
      follow_up_time: interaction.follow_up_time,
      priority: interaction.priority,
      discussion_notes: interaction.discussion_notes,
    });
    setShowModal(true);
  };

  const handleDelete = async (id: number) => {
    if (!confirm('Are you sure you want to delete this interaction?')) return;
    try {
      await api.delete(endpoints.deleteInteraction(id));
      toast.success('Interaction deleted successfully');
      fetchInteractions();
    } catch (error) {
      console.error('Failed to delete interaction:', error);
      toast.error('Failed to delete interaction');
    }
  };

  const handleSaveInteraction = () => {
    setShowModal(false);
    setEditingInteraction(null);
    fetchInteractions();
  };

  const handleCloseModal = () => {
    setShowModal(false);
    setEditingInteraction(null);
  };

  const getPriorityBadgeColor = (priority: string) => {
    switch (priority) {
      case "HIGH":   return "bg-red-100 text-red-700 border-red-200";
      case "MEDIUM": return "bg-yellow-100 text-yellow-700 border-yellow-200";
      case "LOW":    return "bg-green-100 text-green-700 border-green-200";
      default:       return "bg-gray-100 text-gray-700 border-gray-200";
    }
  };

  const formatDate = (dateString: string) => {
    const date = new Date(dateString);
    return date.toLocaleDateString('en-IN', { 
      day: '2-digit', month: 'short', year: 'numeric' 
    });
  };

  const formatTime = (timeString: string) => {
    if (!timeString) return '';
    const [hours, minutes] = timeString.split(':');
    const hour = parseInt(hours);
    const ampm = hour >= 12 ? 'PM' : 'AM';
    const displayHour = hour % 12 || 12;
    return `${displayHour}:${minutes} ${ampm}`;
  };

  const FilterPanel = () => (
    <div className="bg-white rounded-lg shadow-sm p-4">
      <h2 className="font-semibold text-gray-900 mb-4">Filter by Priority</h2>
      <div className="space-y-2">
        {['ALL', 'HIGH', 'MEDIUM', 'LOW'].map((priority) => (
          <div
            key={priority}
            onClick={() => { setSelectedPriority(priority); setShowFilterDrawer(false); }}
            className={`cursor-pointer p-3 rounded-lg transition ${
              selectedPriority === priority
                ? "bg-[#00337C]/11 border-l-4 border-[#00337C]"
                : "hover:bg-gray-50"
            }`}
          >
            <p className="font-medium text-gray-900">
              {priority === 'ALL' ? 'All Interactions' : `${priority} Priority`}
            </p>
            <p className="text-xs text-gray-500 mt-1">
              {priority === 'ALL'
                ? interactions.length
                : interactions.filter(i => i.priority === priority).length
              } items
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
        <main className="flex-1 overflow-y-auto">

          {/* Header */}
          <div className="flex justify-between items-center mb-6 gap-3">
            <h1 className="text-2xl md:text-3xl font-bold text-[#00337C]">Interactions</h1>
            <div className="flex items-center gap-2">
              {/* Mobile filter button */}
              <button
                onClick={() => setShowFilterDrawer(true)}
                className="md:hidden flex items-center gap-2 border border-gray-300 bg-white text-gray-700 px-3 py-2 rounded-lg font-medium text-sm"
              >
                <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M3 4a1 1 0 011-1h16a1 1 0 011 1v2a1 1 0 01-.293.707L13 13.414V19a1 1 0 01-.553.894l-4 2A1 1 0 017 21v-7.586L3.293 6.707A1 1 0 013 6V4z" />
                </svg>
                {selectedPriority !== "ALL" ? (
                  <span className="text-[#00337C] font-semibold">{selectedPriority}</span>
                ) : "Filter"}
              </button>

              <button
                onClick={() => setShowModal(true)}
                className="bg-[#2D8A4E] hover:bg-[#236b3d] transition-colors text-white px-3 md:px-4 py-2 rounded-lg flex items-center gap-2 cursor-pointer font-medium text-sm md:text-base"
              >
                <span className="text-lg">+</span>
                <span>Add Interaction</span>
              </button>
            </div>
          </div>

          {/* Body */}
          <div className="flex gap-6">
            {/* Left Panel - desktop only */}
            <div className="hidden md:block w-64 shrink-0">
              <FilterPanel />
            </div>

            {/* Right Panel - Interactions List */}
            <div className="flex-1 min-w-0">
              <div className="bg-white rounded-lg shadow-sm p-4 md:p-6">
                <div className="flex justify-between items-center mb-4 md:mb-6">
                  <h2 className="text-lg md:text-xl font-semibold text-gray-900">
                    Interactions Overview
                  </h2>
                  <span className="text-xs md:text-sm text-gray-500">
                    {filteredInteractions.length} of {interactions.length}
                  </span>
                </div>

                {loading ? (
                  <div className="text-center py-12">
                    <div className="inline-block animate-spin rounded-full h-10 w-10 border-b-2 border-[#00337C]"></div>
                    <p className="mt-4 text-gray-600">Loading interactions...</p>
                  </div>
                ) : filteredInteractions.length === 0 ? (
                  <div className="text-center py-12">
                    <svg className="mx-auto h-12 w-12 text-gray-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M20 13V6a2 2 0 00-2-2H6a2 2 0 00-2 2v7m16 0v5a2 2 0 01-2 2H6a2 2 0 01-2-2v-5m16 0h-2.586a1 1 0 00-.707.293l-2.414 2.414a1 1 0 01-.707.293h-3.172a1 1 0 01-.707-.293l-2.414-2.414A1 1 0 006.586 13H4" />
                    </svg>
                    <p className="mt-4 text-gray-500">No interactions found</p>
                    <button
                      onClick={() => setShowModal(true)}
                      className="mt-4 text-[#2D8A4E] hover:underline font-medium"
                    >
                      Add your first interaction
                    </button>
                  </div>
                ) : (
                  <div className="space-y-3">
                    {filteredInteractions.map((interaction) => (
                      <div
                        key={interaction.id}
                        className="bg-[#F4F9FD] p-3 md:p-4 rounded-lg hover:shadow-md transition border border-gray-100"
                      >
                        <div className="flex items-start justify-between gap-2">
                          <div className="flex-1 min-w-0">

                            {/* Mobile: 2-col grid */}
                            <div className="grid grid-cols-2 gap-x-4 gap-y-2 md:hidden">
                              <div>
                                <p className="text-xs text-gray-500">Date</p>
                                <p className="text-sm font-medium text-gray-900">{formatDate(interaction.date)}</p>
                              </div>
                              <div>
                                <p className="text-xs text-gray-500">Client</p>
                                <p className="text-sm font-medium text-gray-900 truncate">{interaction.client_name}</p>
                                <p className="text-xs text-gray-500 truncate">{interaction.client_contact}</p>
                              </div>
                              <div>
                                <p className="text-xs text-gray-500">Representative</p>
                                <p className="text-sm font-medium text-gray-900 truncate">{interaction.employee_name}</p>
                              </div>
                              <div>
                                <p className="text-xs text-gray-500">Follow-up</p>
                                <p className="text-sm font-medium text-gray-900">{formatDate(interaction.follow_up_date)}</p>
                                <p className="text-xs text-gray-600">{formatTime(interaction.follow_up_time)}</p>
                              </div>
                              <div className="col-span-2">
                                <p className="text-xs text-gray-500">Priority</p>
                                <span className={`inline-flex px-3 py-1 rounded-full text-xs font-semibold border ${getPriorityBadgeColor(interaction.priority)}`}>
                                  {interaction.priority_display}
                                </span>
                              </div>
                            </div>

                            {/* Desktop: 5-col grid */}
                            <div className="hidden md:grid grid-cols-5 gap-4">
                              <div>
                                <p className="text-xs text-gray-500 mb-1">Date</p>
                                <p className="text-sm font-medium text-gray-900">{formatDate(interaction.date)}</p>
                              </div>
                              <div>
                                <p className="text-xs text-gray-500 mb-1">Client</p>
                                <p className="text-sm font-medium text-gray-900">{interaction.client_name}</p>
                                <p className="text-xs text-gray-500">{interaction.client_contact}</p>
                              </div>
                              <div>
                                <p className="text-xs text-gray-500 mb-1">Representative</p>
                                <p className="text-sm font-medium text-gray-900">{interaction.employee_name}</p>
                              </div>
                              <div>
                                <p className="text-xs text-gray-500 mb-1">Follow-up</p>
                                <p className="text-sm font-medium text-gray-900">{formatDate(interaction.follow_up_date)}</p>
                                <p className="text-xs text-gray-600">{formatTime(interaction.follow_up_time)}</p>
                              </div>
                              <div>
                                <p className="text-xs text-gray-500 mb-1">Priority</p>
                                <span className={`inline-flex px-3 py-1 rounded-full text-xs font-semibold border ${getPriorityBadgeColor(interaction.priority)}`}>
                                  {interaction.priority_display}
                                </span>
                              </div>
                            </div>

                          </div>

                          {/* Action Buttons */}
                          <div className="flex items-center gap-1 shrink-0">
                            <button
                              onClick={() => handleEdit(interaction)}
                              className="p-2 text-blue-600 hover:bg-blue-50 rounded-lg transition"
                              title="Edit"
                            >
                              <svg className="w-4 h-4 md:w-5 md:h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z" />
                              </svg>
                            </button>
                            <button
                              onClick={() => handleDelete(interaction.id)}
                              className="p-2 text-red-600 hover:bg-red-50 rounded-lg transition"
                              title="Delete"
                            >
                              <svg className="w-4 h-4 md:w-5 md:h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
                              </svg>
                            </button>
                          </div>
                        </div>

                        {/* Discussion Notes */}
                        {interaction.discussion_notes && (
                          <div className="mt-3 pt-3 border-t border-gray-200">
                            <p className="text-xs text-gray-500 mb-1">Notes</p>
                            <p className="text-sm text-gray-700">{interaction.discussion_notes}</p>
                          </div>
                        )}
                      </div>
                    ))}
                  </div>
                )}
              </div>
            </div>
          </div>
        </main>
      </div>

      <AddInteractionModal
        isOpen={showModal}
        onClose={handleCloseModal}
        onSave={handleSaveInteraction}
        initialData={editingInteraction}
      />
    </div>
  );
};

export default InteractionsPage;