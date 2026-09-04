export interface Employee {
  id: string;
  name: string;
  department: string;
  level: 'Junior' | 'Middle' | 'Senior';
  avatar: string;
}

export interface Reminder {
  id: string;
  title: string;
  date: string;
  time: string;
  duration: string;
  status: 'upcoming' | 'in-progress' | 'completed';
}

export interface ProductSale {
  id: string;
  clientName: string;
  type: string;
  amount: number;
  category: number;
  createdDate: string;
  priority: 'Low' | 'Medium' | 'High';
  representatives: string[];
}

type SalesRow = {
  id: number;
  client: string;
  date: string;
  contactNo: string;
  salesRep: string;
  salesRepId: number; // ADD THIS
  product: 'Yes' | 'No';
  company: string;
  amount: string;
  remark: string;
};

type InteractionRow = {
  id: number;
  client: string;
  date: string;
  contactNo: string;
  summary: string;
  callStatus: 'Yes' | 'No';
  followUpDate: string;
  followUpTime: string;
  employeeId: number; // ADD THIS
};