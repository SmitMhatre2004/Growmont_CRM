"use client";

import React, { createContext, useContext, useState, useEffect } from 'react';
import { useRouter, usePathname } from 'next/navigation';

interface User {
    id: number;
    name: string;
    email: string;
    avatar: string | null;
    role: 'ADMIN' | 'EMPLOYEE';
}

interface AuthContextType {
    user: User | null;
    token: string | null;
    login: (userData: User, accessToken: string, refreshToken: string) => void;
    logout: () => void;
    isLoading: boolean;
}

const AuthContext = createContext<AuthContextType | undefined>(undefined);

export function AuthProvider({ children }: { children: React.ReactNode }) {
    const [user, setUser] = useState<User | null>(null);
    const [token, setToken] = useState<string | null>(null);
    const [isLoading, setIsLoading] = useState(true);
    const router = useRouter();
    const pathname = usePathname();

    useEffect(() => {
        // Check local storage on load
        const storedUser = localStorage.getItem('user');
        const storedToken = localStorage.getItem('accessToken');
        
        if (storedUser && storedToken) {
            try {
                const parsedUser = JSON.parse(storedUser);
                setUser(parsedUser);
                setToken(storedToken);
                console.log('User restored from localStorage:', parsedUser);
            } catch (e) {
                console.error("Failed to parse user from local storage", e);
                localStorage.removeItem('user');
                localStorage.removeItem('accessToken');
                localStorage.removeItem('refreshToken');
            }
        }
        setIsLoading(false);
    }, []);

    const login = (userData: User, accessToken: string, refreshToken: string) => {
        console.log('Login called with:', userData);
        
        setUser(userData);
        setToken(accessToken);
        
        localStorage.setItem('user', JSON.stringify(userData));
        localStorage.setItem('accessToken', accessToken);
        localStorage.setItem('refreshToken', refreshToken);
        
        console.log('User data saved to localStorage');
        
        // Use window.location for a hard redirect to ensure state updates
        window.location.href = '/dashboard';
    };

    const logout = async () => {
        console.log('Logout called');
        
        const refreshToken = localStorage.getItem('refreshToken');
        const API_URL = process.env.NEXT_PUBLIC_API_URL || 'http://127.0.0.1:8000';

        // Call logout API
        if (refreshToken) {
            try {
                await fetch(`${API_URL}/api/auth/logout/`, {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json',
                        'Authorization': `Bearer ${token}`,
                    },
                    body: JSON.stringify({ refresh: refreshToken }),
                });
            } catch (error) {
                console.error('Logout API error:', error);
            }
        }
        
        // Clear state
        setUser(null);
        setToken(null);
        
        // Clear localStorage
        localStorage.removeItem('user');
        localStorage.removeItem('accessToken');
        localStorage.removeItem('refreshToken');
        
        console.log('User logged out, redirecting to /');
        
        // Redirect to home page (/)
        window.location.href = '/';
    };

    return (
        <AuthContext.Provider value={{ user, token, login, logout, isLoading }}>
            {children}
        </AuthContext.Provider>
    );
}

export function useAuth() {
    const context = useContext(AuthContext);
    if (!context) {
        throw new Error('useAuth must be used within an AuthProvider');
    }
    return context;
}