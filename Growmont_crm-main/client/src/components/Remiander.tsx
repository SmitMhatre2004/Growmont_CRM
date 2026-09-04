'use client';

import Link from 'next/link';
import React from 'react';

interface Reminder {
  id: string;
  title: string;
  date: string;
  time: string;
  duration: string;
  status: 'upcoming' | 'in-progress' | 'completed';
}

interface RemindersProps {
  reminders: Reminder[];
}

const Reminders: React.FC<RemindersProps> = ({ reminders }) => {
  const getStatusIcon = (status: string) => {
    if (status === 'upcoming') {
      return (
        <svg className="w-4 h-4 text-orange-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 10l7-7m0 0l7 7m-7-7v18" />
        </svg>
      );
    }
    return (
      <svg className="w-4 h-4 text-green-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 14l-7 7m0 0l-7-7m7 7V3" />
      </svg>
    );
  };

  const getStatusColor = (status: string) => {
    if (status === 'upcoming') return 'border-l-orange-500';
    return 'border-l-green-500';
  };

  return (
    <div className="sticky top-20 bg-white rounded-3xl border border-gray-200 p-5">
      <div className="flex items-center justify-between mb-4">
        <h2 className="text-lg font-semibold text-gray-900">Your Reminders</h2>
        <Link href="/profile">
        <button className="text-sm text-[#3B5BA5] cursor-pointer font-medium">
          View all →
        </button>
        </Link>
      </div>

      {/* Reminders List */}
      <div className="space-y-3">
        {reminders.map((reminder) => (
          <div
            key={reminder.id}
            className={`border-l-4 ${getStatusColor(reminder.status)} bg-gray-50 p-4 rounded-r-lg`}
          >
            <div className="flex items-start justify-between">
              <div className="flex-1">
                <h3 className="font-medium text-gray-900 mb-2">{reminder.title}</h3>
                <div className="flex items-center gap-4 text-sm text-gray-600">
                  <span>{reminder.date} | {reminder.time}</span>
                  <div className="flex items-center gap-1">
                    <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z" />
                    </svg>
                    <span>{reminder.duration}</span>
                  </div>
                </div>
              </div>
              <div className="ml-2">
                {getStatusIcon(reminder.status)}
              </div>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
};

export default Reminders;