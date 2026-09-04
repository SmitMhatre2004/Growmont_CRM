"use client";

import { useEffect } from 'react';
import { useRouter } from 'next/navigation';
import LoginPage from '@/components/Login';

const Home = () => {
  const router = useRouter();

  useEffect(() => {
    // Check if user is already logged in
    const user = localStorage.getItem('user');
    const token = localStorage.getItem('accessToken');
    
    if (user && token) {
      console.log('User already logged in, redirecting to dashboard');
      router.push('/dashboard');
    }
  }, [router]);

  return (
    <div>
      <LoginPage />
    </div>
  );
};

export default Home;