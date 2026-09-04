'use client';

import { useEffect, useState } from 'react';
import Sidebar from '@/components/Sidebar';
import Navbar from '@/components/Navbar';
import toast from 'react-hot-toast';
import { Trash2, Edit } from 'lucide-react';
import AddSalesModal from '@/components/AddSalesModal';
import AddInteractionModal from '@/components/AddInteractionsModal';

type SalesRow = {
  id: number;
  client_name: string;
  date: string;
  sales_rep_name: string;
  sales_rep_id: number;
  product: string;
  product_display: string;
  frequency: string;
  frequency_display: string;
  company: string;
  scheme: string;
  amount: string;
  remarks: string;
};

type InteractionRow = {
  id: number;
  client_name: string;
  client_contact: string;
  date: string;
  employee_name: string;
  employee_id: number;
  discussion_notes: string;
  priority: string;
  priority_display: string;
  follow_up_date: string;
  follow_up_time: string;
};

export default function InfoPortalPage() {
  const [showModal, setShowModal] = useState(false);
  const [search, setSearch] = useState('');
  const [activeTab, setActiveTab] = useState<'sales' | 'interactions'>('interactions');

  const [sales, setSales] = useState<SalesRow[]>([]);
  const [interactions, setInteractions] = useState<InteractionRow[]>([]);
  const [selectedRows, setSelectedRows] = useState<number[]>([]);
  const [filters, setFilters] = useState({
    dateFrom: '',
    dateTo: '',
    client: '',
    salesRep: '',
    product: '',
    priority: '',
  });
  const [showFilters, setShowFilters] = useState(false);

  const [editingRow, setEditingRow] = useState<SalesRow | InteractionRow | null>(null);
  const [showEditModal, setShowEditModal] = useState(false);

  const productOptions = [
    { value: '', label: 'All Products' },
    { value: 'MF', label: 'Mutual Funds' },
    { value: 'HI', label: 'Health Insurance' },
    { value: 'GI', label: 'General Insurance' },
    { value: 'LI', label: 'Life Insurance' },
    { value: 'NCD', label: 'NCDs' },
    { value: 'MLD', label: 'MLDs' },
    { value: 'BOND', label: 'Bonds' },
    { value: 'CFD', label: 'Corporate FDs' },
    { value: 'AIF', label: 'AIFs' },
    { value: 'PMS', label: 'PMS' },
    { value: 'ADV', label: 'Advisory' },
    { value: 'SB', label: 'Shares Broking' },
    { value: 'US', label: 'Unlisted Shares' },
    { value: 'RE', label: 'Real Estate' },
    { value: 'LOAN', label: 'Loans' },
    { value: 'WILL', label: 'Will Making' },
  ];

  const priorityOptions = [
    { value: '', label: 'All Priorities' },
    { value: 'HIGH', label: 'High' },
    { value: 'MEDIUM', label: 'Medium' },
    { value: 'LOW', label: 'Low' },
  ];

  const filteredSales = sales.filter(s => {
    const matchesSearch = s.client_name.toLowerCase().includes(search.toLowerCase());
    const matchesDateFrom = !filters.dateFrom || s.date >= filters.dateFrom;
    const matchesDateTo = !filters.dateTo || s.date <= filters.dateTo;
    const matchesClient = !filters.client || s.client_name.toLowerCase().includes(filters.client.toLowerCase());
    const matchesSalesRep = !filters.salesRep || s.sales_rep_name.toLowerCase().includes(filters.salesRep.toLowerCase());
    const matchesProduct = !filters.product || s.product === filters.product;
    return matchesSearch && matchesDateFrom && matchesDateTo && matchesClient && matchesSalesRep && matchesProduct;
  });

  const filteredInteractions = interactions.filter(i => {
    const matchesSearch = i.client_name.toLowerCase().includes(search.toLowerCase());
    const matchesDateFrom = !filters.dateFrom || i.date >= filters.dateFrom;
    const matchesDateTo = !filters.dateTo || i.date <= filters.dateTo;
    const matchesClient = !filters.client || i.client_name.toLowerCase().includes(filters.client.toLowerCase());
    const matchesPriority = !filters.priority || i.priority === filters.priority;
    return matchesSearch && matchesDateFrom && matchesDateTo && matchesClient && matchesPriority;
  });

  // const API_URL = process.env.NEXT_PUBLIC_API_URL || 'http://127.0.0.1:8000';
const API_URL = "";

  useEffect(() => {
    const token = localStorage.getItem('accessToken');

    fetch(`${API_URL}/api/sales/`, { headers: { 'Authorization': `Bearer ${token}` } })
      .then(res => {
        if (res.status === 401) { toast.error('Session expired.'); window.location.href = '/'; return []; }
        return res.ok ? res.json() : [];
      })
      .then(dbSales => {
        if (dbSales.length) {
          setSales(dbSales.map((s: any) => ({
            id: s.id, client_name: s.client_name || 'Unknown', date: s.date,
            sales_rep_name: s.sales_rep_name || 'Unassigned', sales_rep_id: s.sales_rep_id,
            product: s.product, product_display: s.product_display,
            frequency: s.frequency, frequency_display: s.frequency_display,
            company: s.company, scheme: s.scheme, amount: s.amount, remarks: s.remarks || '',
          })));
        }
      })
      .catch(() => toast.error('Failed to load sales'));

    fetch(`${API_URL}/api/interactions/`, { headers: { 'Authorization': `Bearer ${token}` } })
      .then(res => {
        if (res.status === 401) { toast.error('Session expired.'); window.location.href = '/'; return []; }
        return res.ok ? res.json() : [];
      })
      .then(dbInteractions => {
        if (dbInteractions.length) {
          setInteractions(dbInteractions.map((i: any) => ({
            id: i.id, client_name: i.client_name || 'Unknown', client_contact: i.client_contact || '',
            date: i.date, employee_name: i.employee_name || 'Unassigned', employee_id: i.employee_id,
            discussion_notes: i.discussion_notes || '', priority: i.priority,
            priority_display: i.priority_display, follow_up_date: i.follow_up_date, follow_up_time: i.follow_up_time,
          })));
        }
      })
      .catch(() => toast.error('Failed to load interactions'));
  }, []);

  const handleExport = async () => {
    const dataToExport = activeTab === 'sales' ? filteredSales : filteredInteractions;
    if (dataToExport.length === 0) { toast.error('No data to export'); return; }

    const exportPayload = {
      data: dataToExport.map(row => {
        if (activeTab === 'sales') {
          const s = row as SalesRow;
          return { client_name: s.client_name, date: s.date, sales_rep: s.sales_rep_name, product: s.product_display, company: s.company, scheme: s.scheme, amount: s.amount, frequency: s.frequency_display, remarks: s.remarks };
        } else {
          const i = row as InteractionRow;
          return { client_name: i.client_name, client_contact: i.client_contact, date: i.date, employee: i.employee_name, discussion_notes: i.discussion_notes, priority: i.priority_display, follow_up_date: i.follow_up_date, follow_up_time: i.follow_up_time };
        }
      }),
    };

    const url = activeTab === 'sales' ? `${API_URL}/api/export/sales/filtered/` : `${API_URL}/api/export/interactions/filtered/`;
    try {
      const response = await fetch(url, {
        method: 'POST',
        headers: { 'Authorization': `Bearer ${localStorage.getItem('accessToken')}`, 'Content-Type': 'application/json' },
        body: JSON.stringify(exportPayload),
      });
      if (!response.ok) throw new Error('Export failed');
      const blob = await response.blob();
      const downloadUrl = window.URL.createObjectURL(blob);
      const link = document.createElement('a');
      link.href = downloadUrl;
      link.download = activeTab === 'sales' ? 'filtered_sales.xlsx' : 'filtered_interactions.xlsx';
      document.body.appendChild(link);
      link.click();
      link.remove();
      window.URL.revokeObjectURL(downloadUrl);
      toast.success(`Exported ${dataToExport.length} ${activeTab}`);
    } catch { toast.error('Export failed'); }
  };

  const handleImport = async (e: React.ChangeEvent<HTMLInputElement>) => {
    if (!e.target.files?.length) return;
    const formData = new FormData();
    formData.append('file', e.target.files[0]);
    const url = activeTab === 'sales' ? `${API_URL}/api/import/sales/` : `${API_URL}/api/import/interactions/`;
    try {
      const response = await fetch(url, { method: 'POST', headers: { 'Authorization': `Bearer ${localStorage.getItem('accessToken')}` }, body: formData });
      if (response.ok) { toast.success('Imported successfully!'); window.location.reload(); }
      else toast.error('Import failed');
    } catch { toast.error('Import failed'); }
  };

  const handleAdd = async (payload: any) => {
    const url = activeTab === 'sales' ? `${API_URL}/api/sales/create/` : `${API_URL}/api/interactions/create/`;
    const res = await fetch(url, { method: 'POST', headers: { 'Authorization': `Bearer ${localStorage.getItem('accessToken')}`, 'Content-Type': 'application/json' }, body: JSON.stringify(payload) });
    if (res.ok) { toast.success('Added successfully'); setShowModal(false); window.location.reload(); }
    else toast.error('Failed to add');
  };

  const handleEdit = async (payload: any) => {
    if (!editingRow) return;
    const url = activeTab === 'sales' ? `${API_URL}/api/sales/${editingRow.id}/update/` : `${API_URL}/api/interactions/${editingRow.id}/update/`;
    const res = await fetch(url, { method: 'PUT', headers: { 'Authorization': `Bearer ${localStorage.getItem('accessToken')}`, 'Content-Type': 'application/json' }, body: JSON.stringify(payload) });
    if (res.ok) { toast.success('Updated successfully'); setShowEditModal(false); setEditingRow(null); window.location.reload(); }
    else toast.error('Failed to update');
  };

  const openEditModal = (row: SalesRow | InteractionRow) => { setEditingRow(row); setShowEditModal(true); };

  const handleDelete = async (id: number) => {
    const url = activeTab === 'sales' ? `${API_URL}/api/sales/${id}/delete/` : `${API_URL}/api/interactions/${id}/delete/`;
    const res = await fetch(url, { headers: { 'Authorization': `Bearer ${localStorage.getItem('accessToken')}`, 'Content-Type': 'application/json' }, method: 'DELETE' });
    if (res.ok) {
      toast.success('Deleted');
      if (activeTab === 'sales') setSales(prev => prev.filter(r => r.id !== id));
      else setInteractions(prev => prev.filter(r => r.id !== id));
    } else toast.error('Delete failed');
  };
  

  const handleBulkDelete = async () => {
    if (selectedRows.length === 0) { toast.error('No rows selected'); return; }
    if (!confirm(`Delete ${selectedRows.length} item(s)?`)) return;
    await Promise.all(selectedRows.map(id => handleDelete(id)));
    setSelectedRows([]);
  };

  const toggleRowSelection = (id: number) => {
    setSelectedRows(prev => prev.includes(id) ? prev.filter(rowId => rowId !== id) : [...prev, id]);
  };

  const toggleSelectAll = () => {
    const currentData = activeTab === 'sales' ? filteredSales : filteredInteractions;
    if (selectedRows.length === currentData.length) setSelectedRows([]);
    else setSelectedRows(currentData.map(row => row.id));
  };

  const resetFilters = () => setFilters({ dateFrom: '', dateTo: '', client: '', salesRep: '', product: '', priority: '' });

  const formatAmount = (amount: string) => new Intl.NumberFormat('en-IN', { style: 'currency', currency: 'INR', maximumFractionDigits: 0 }).format(parseFloat(amount));

  return (
    <div className="bg-[#F6FAFD] min-h-screen">
      <Sidebar />
      <Navbar />

      <div className="md:ml-64 mt-[4rem] md:mt-16">
        <div className="p-4 md:p-6">

          {/* TABS */}
          <div className="flex bg-gray-200 rounded-3xl p-1 w-fit mb-6">
            <button
              onClick={() => setActiveTab('sales')}
              className={`px-5 md:px-6 py-2 rounded-3xl font-medium transition-colors text-sm md:text-base ${activeTab === 'sales' ? 'bg-[#2D8A4E] text-white' : 'text-gray-600 hover:text-gray-900'}`}
            >
              Sales
            </button>
            <button
              onClick={() => setActiveTab('interactions')}
              className={`px-5 md:px-6 py-2 rounded-3xl font-medium transition-colors text-sm md:text-base ${activeTab === 'interactions' ? 'bg-[#2D8A4E] text-white' : 'text-gray-600 hover:text-gray-900'}`}
            >
              Interactions
            </button>
          </div>

          {/* CARD */}
          <div className="bg-white rounded-2xl p-4 md:p-5 shadow-sm">

            {/* Card Header */}
            <div className="flex flex-col gap-3 mb-4 md:flex-row md:justify-between md:items-center">
              <div>
                <h2 className="text-lg font-semibold capitalize">
                  {activeTab === 'sales' ? 'Sales' : 'Client Interactions'}
                </h2>
                <p className="text-sm text-gray-500">
                  Manage and track all {activeTab === 'sales' ? 'sales' : 'interactions'}
                </p>
              </div>

              {/* Action buttons - wrap on mobile */}
              <div className="flex flex-wrap gap-2">
                <button
                  onClick={handleBulkDelete}
                  disabled={selectedRows.length === 0}
                  className={`px-3 py-2 text-sm border rounded-lg ${selectedRows.length > 0 ? 'hover:bg-red-50 hover:border-red-300' : 'opacity-50 cursor-not-allowed'}`}
                >
                  Delete {selectedRows.length > 0 && `(${selectedRows.length})`}
                </button>

                <button
                  onClick={() => setShowFilters(!showFilters)}
                  className={`px-3 py-2 text-sm border rounded-lg ${showFilters ? 'bg-gray-100' : ''}`}
                >
                  Filters
                </button>

                <label className="px-3 py-2 text-sm border rounded-lg cursor-pointer hover:bg-gray-50">
                  Import
                  <input type="file" hidden accept=".xlsx" onChange={handleImport} />
                </label>

                <button
                  onClick={handleExport}
                  className="px-3 py-2 text-sm border rounded-lg hover:bg-gray-50"
                >
                  Export ({activeTab === 'sales' ? filteredSales.length : filteredInteractions.length})
                </button>

                <button
                  onClick={() => setShowModal(true)}
                  className="px-3 py-2 text-sm cursor-pointer bg-[#2D8A4E] text-white rounded-lg hover:bg-[#246b3d]"
                >
                  + Add new
                </button>
              </div>
            </div>

            {/* FILTERS PANEL */}
            {showFilters && (
              <div className="my-4 p-4 bg-gray-50 rounded-lg border">
                <div className="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-4 gap-4">
                  <div>
                    <label className="block text-sm font-medium mb-1">Date From</label>
                    <input type="date" value={filters.dateFrom}
                      onChange={(e) => setFilters({ ...filters, dateFrom: e.target.value })}
                      className="w-full px-3 py-2 border rounded-lg text-sm" />
                  </div>
                  <div>
                    <label className="block text-sm font-medium mb-1">Date To</label>
                    <input type="date" value={filters.dateTo}
                      onChange={(e) => setFilters({ ...filters, dateTo: e.target.value })}
                      className="w-full px-3 py-2 border rounded-lg text-sm" />
                  </div>
                  <div>
                    <label className="block text-sm font-medium mb-1">Client Name</label>
                    <input type="text" value={filters.client}
                      onChange={(e) => setFilters({ ...filters, client: e.target.value })}
                      placeholder="Search client..."
                      className="w-full px-3 py-2 border rounded-lg text-sm" />
                  </div>

                  {activeTab === 'sales' ? (
                    <>
                      <div>
                        <label className="block text-sm font-medium mb-1">Sales Rep</label>
                        <input type="text" value={filters.salesRep}
                          onChange={(e) => setFilters({ ...filters, salesRep: e.target.value })}
                          placeholder="Search sales rep..."
                          className="w-full px-3 py-2 border rounded-lg text-sm" />
                      </div>
                      <div>
                        <label className="block text-sm font-medium mb-1">Product</label>
                        <select value={filters.product}
                          onChange={(e) => setFilters({ ...filters, product: e.target.value })}
                          className="w-full px-3 py-2 border rounded-lg text-sm">
                          {productOptions.map(opt => <option key={opt.value} value={opt.value}>{opt.label}</option>)}
                        </select>
                      </div>
                    </>
                  ) : (
                    <div>
                      <label className="block text-sm font-medium mb-1">Priority</label>
                      <select value={filters.priority}
                        onChange={(e) => setFilters({ ...filters, priority: e.target.value })}
                        className="w-full px-3 py-2 border rounded-lg text-sm">
                        {priorityOptions.map(opt => <option key={opt.value} value={opt.value}>{opt.label}</option>)}
                      </select>
                    </div>
                  )}
                </div>

                <div className="mt-3 flex gap-2 items-center flex-wrap">
                  <button onClick={resetFilters} className="px-4 py-2 text-sm bg-gray-200 rounded-lg hover:bg-gray-300">
                    Reset Filters
                  </button>
                  <span className="text-sm text-gray-600">
                    Showing {activeTab === 'sales' ? filteredSales.length : filteredInteractions.length} results
                  </span>
                </div>
              </div>
            )}

            {/* TABLES - always scrollable horizontally */}
            {activeTab === 'sales' ? (
              <div className="overflow-x-auto -mx-4 md:mx-0">
                <div className="min-w-[800px] px-4 md:px-0">
                  <table className="w-full text-sm">
                    <thead className="bg-gray-50 border-b">
                      <tr>
                        <th className="py-3 px-3 text-left">
                          <input type="checkbox"
                            checked={selectedRows.length === filteredSales.length && filteredSales.length > 0}
                            onChange={toggleSelectAll} className="rounded" />
                        </th>
                        <th className="py-3 px-3 text-left font-semibold text-gray-600">Client</th>
                        <th className="py-3 px-3 text-center font-semibold text-gray-600">Date</th>
                        <th className="py-3 px-3 text-center font-semibold text-gray-600">Sales Rep</th>
                        <th className="py-3 px-3 text-center font-semibold text-gray-600">Product</th>
                        <th className="py-3 px-3 text-center font-semibold text-gray-600">Company</th>
                        <th className="py-3 px-3 text-center font-semibold text-gray-600">Scheme</th>
                        <th className="py-3 px-3 text-right font-semibold text-gray-600">Amount</th>
                        <th className="py-3 px-3 text-center font-semibold text-gray-600">Frequency</th>
                        <th className="py-3 px-3 text-center font-semibold text-gray-600">Actions</th>
                      </tr>
                    </thead>
                    <tbody>
                      {filteredSales.length === 0 ? (
                        <tr><td colSpan={10} className="py-8 text-center text-gray-500">No sales found</td></tr>
                      ) : (
                        filteredSales.map(row => (
                          <tr key={row.id} className="border-b last:border-none hover:bg-gray-50">
                            <td className="py-3 px-3">
                              <input type="checkbox" checked={selectedRows.includes(row.id)}
                                onChange={() => toggleRowSelection(row.id)} className="rounded" />
                            </td>
                            <td className="py-3 px-3 font-medium whitespace-nowrap">{row.client_name}</td>
                            <td className="py-3 px-3 text-center whitespace-nowrap">{row.date}</td>
                            <td className="py-3 px-3 text-center whitespace-nowrap">{row.sales_rep_name}</td>
                            <td className="py-3 px-3 text-center whitespace-nowrap">{row.product_display}</td>
                            <td className="py-3 px-3 text-center whitespace-nowrap">{row.company}</td>
                            <td className="py-3 px-3 text-center whitespace-nowrap">{row.scheme}</td>
                            <td className="py-3 px-3 text-right font-semibold whitespace-nowrap">{formatAmount(row.amount)}</td>
                            <td className="py-3 px-3 text-center whitespace-nowrap">{row.frequency_display}</td>
                            <td className="py-3 px-3">
                              <div className="flex items-center justify-center gap-2">
                                <button onClick={() => openEditModal(row)} className="p-1.5 text-blue-600 hover:bg-blue-50 rounded transition-colors" title="Edit">
                                  <Edit size={16} />
                                </button>
                                <button onClick={() => handleDelete(row.id)} className="p-1.5 text-red-600 hover:bg-red-50 rounded transition-colors" title="Delete">
                                  <Trash2 size={16} />
                                </button>
                              </div>
                            </td>
                          </tr>
                        ))
                      )}
                    </tbody>
                  </table>
                </div>
              </div>
            ) : (
              <div className="overflow-x-auto -mx-4 md:mx-0">
                <div className="min-w-[900px] px-4 md:px-0">
                  <table className="w-full text-sm">
                    <thead className="bg-gray-50 border-b">
                      <tr>
                        <th className="py-3 px-3 text-left">
                          <input type="checkbox"
                            checked={selectedRows.length === filteredInteractions.length && filteredInteractions.length > 0}
                            onChange={toggleSelectAll} className="rounded" />
                        </th>
                        <th className="py-3 px-3 text-left font-semibold text-gray-600">Client</th>
                        <th className="py-3 px-3 text-center font-semibold text-gray-600">Contact</th>
                        <th className="py-3 px-3 text-center font-semibold text-gray-600">Date</th>
                        <th className="py-3 px-3 text-center font-semibold text-gray-600">Representative</th>
                        <th className="py-3 px-3 text-left font-semibold text-gray-600">Discussion Notes</th>
                        <th className="py-3 px-3 text-center font-semibold text-gray-600">Priority</th>
                        <th className="py-3 px-3 text-center font-semibold text-gray-600">Follow-up Date</th>
                        <th className="py-3 px-3 text-center font-semibold text-gray-600">Follow-up Time</th>
                        <th className="py-3 px-3 text-center font-semibold text-gray-600">Actions</th>
                      </tr>
                    </thead>
                    <tbody>
                      {filteredInteractions.length === 0 ? (
                        <tr><td colSpan={10} className="py-8 text-center text-gray-500">No interactions found</td></tr>
                      ) : (
                        filteredInteractions.map(row => (
                          <tr key={row.id} className="border-b last:border-none hover:bg-gray-50">
                            <td className="py-3 px-3">
                              <input type="checkbox" checked={selectedRows.includes(row.id)}
                                onChange={() => toggleRowSelection(row.id)} className="rounded" />
                            </td>
                            <td className="py-3 px-3 font-medium whitespace-nowrap">{row.client_name}</td>
                            <td className="py-3 px-3 text-center whitespace-nowrap">{row.client_contact}</td>
                            <td className="py-3 px-3 text-center whitespace-nowrap">{row.date}</td>
                            <td className="py-3 px-3 text-center whitespace-nowrap">{row.employee_name}</td>
                            <td className="py-3 px-3 text-left max-w-[200px] truncate">{row.discussion_notes}</td>
                            <td className="py-3 px-3 text-center">
                              <span className={`px-2 py-1 rounded-full text-xs font-semibold whitespace-nowrap ${
                                row.priority === 'HIGH' ? 'bg-red-100 text-red-700' :
                                row.priority === 'MEDIUM' ? 'bg-yellow-100 text-yellow-700' :
                                'bg-green-100 text-green-700'
                              }`}>
                                {row.priority_display}
                              </span>
                            </td>
                            <td className="py-3 px-3 text-center whitespace-nowrap">{row.follow_up_date}</td>
                            <td className="py-3 px-3 text-center whitespace-nowrap">{row.follow_up_time}</td>
                            <td className="py-3 px-3">
                              <div className="flex items-center justify-center gap-2">
                                <button onClick={() => openEditModal(row)} className="p-1.5 text-blue-600 hover:bg-blue-50 rounded transition-colors" title="Edit">
                                  <Edit size={16} />
                                </button>
                                <button onClick={() => handleDelete(row.id)} className="p-1.5 text-red-600 hover:bg-red-50 rounded transition-colors" title="Delete">
                                  <Trash2 size={16} />
                                </button>
                              </div>
                            </td>
                          </tr>
                        ))
                      )}
                    </tbody>
                  </table>
                </div>
              </div>
            )}
          </div>
        </div>
      </div>

      {/* MODALS */}
      {activeTab === 'sales' ? (
        <>
          <AddSalesModal isOpen={showModal} onClose={() => setShowModal(false)} onSave={(payload: any) => handleAdd(payload)} />
          {editingRow && (
            <AddSalesModal
              isOpen={showEditModal}
              onClose={() => { setShowEditModal(false); setEditingRow(null); }}
              onSave={(payload: any) => handleEdit(payload)}
              initialData={{
                id: (editingRow as SalesRow).id, date: (editingRow as SalesRow).date,
                client_name: (editingRow as SalesRow).client_name, sales_rep: (editingRow as SalesRow).sales_rep_id,
                product: (editingRow as SalesRow).product, company: (editingRow as SalesRow).company,
                scheme: (editingRow as SalesRow).scheme, amount: (editingRow as SalesRow).amount,
                frequency: (editingRow as SalesRow).frequency, remarks: (editingRow as SalesRow).remarks,
              }}
            />
          )}
        </>
      ) : (
        <>
          <AddInteractionModal isOpen={showModal} onClose={() => setShowModal(false)} onSave={(payload: any) => handleAdd(payload)} />
          {editingRow && (
            <AddInteractionModal
              isOpen={showEditModal}
              onClose={() => { setShowEditModal(false); setEditingRow(null); }}
              onSave={(payload: any) => handleEdit(payload)}
              initialData={{
                id: (editingRow as InteractionRow).id, date: (editingRow as InteractionRow).date,
                client_name: (editingRow as InteractionRow).client_name, client_contact: (editingRow as InteractionRow).client_contact,
                employee: (editingRow as InteractionRow).employee_id, discussion_notes: (editingRow as InteractionRow).discussion_notes,
                priority: (editingRow as InteractionRow).priority, follow_up_date: (editingRow as InteractionRow).follow_up_date,
                follow_up_time: (editingRow as InteractionRow).follow_up_time,
              }}
            />
          )}
        </>
      )}
    </div>
  );
}