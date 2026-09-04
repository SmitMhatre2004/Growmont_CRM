'use client';

import React, { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';

const Navbar: React.FC = () => {
  const router = useRouter();
  const [userName, setUserName] = useState('User');
  const [userInitials, setUserInitials] = useState('U');

  useEffect(() => {
    // Get user data from localStorage
    const user = JSON.parse(localStorage.getItem('user') || '{}');
    
    if (user.name) {
      setUserName(user.name);
      // Get initials from name
      const initials = user.name
        .split(' ')
        .map((n: string) => n[0])
        .join('')
        .toUpperCase()
        .slice(0, 2); // Max 2 initials
      setUserInitials(initials);
    }
  }, []);

  return (
    <nav className="fixed top-0 left-64 right-0 h-16 bg-white border-b border-gray-200 z-10">
      <div className="h-full px-6 flex items-center justify-end">
        {/* User Profile - Right Corner */}
        <div 
          onClick={() => router.push('/profile')}
          className="flex items-center gap-2 p-2 hover:bg-gray-100 rounded-2xl cursor-pointer transition-colors"
        >
          <div className="w-10 h-10 rounded-full bg-gradient-to-br from-blue-400 to-purple-500 flex items-center justify-center text-white font-semibold">
            {userInitials}
          </div>
          <div className="flex items-center gap-1">
            <span className="font-medium text-gray-900">{userName}</span>
            <svg className="w-4 h-4 text-gray-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 9l-7 7-7-7" />
            </svg>
          </div>
        </div>
      </div>
    </nav>
  );
};

export default Navbar;