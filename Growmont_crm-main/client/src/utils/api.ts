

// const API_URL = process.env.NEXT_PUBLIC_API_URL || 'http://127.0.0.1:8000';
const API_URL = "";

interface FetchOptions extends RequestInit {
  requireAuth?: boolean;
}


export async function apiFetch(
  endpoint: string,
  options: FetchOptions = {}
): Promise<Response> {
  const { requireAuth = true, headers = {}, ...restOptions } = options;

  const config: RequestInit = {
    ...restOptions,
    headers: {
      'Content-Type': 'application/json',
      ...headers,
    },
  };

  // Add authentication token if required
  if (requireAuth) {
    const token = localStorage.getItem('accessToken');
    
    if (!token) {
      // Redirect to login if no token
      window.location.href = '/';
      throw new Error('No authentication token found');
    }

    config.headers = {
      ...config.headers,
      Authorization: `Bearer ${token}`,
    };
  }

  const url = endpoint.startsWith('http') ? endpoint : `${API_URL}${endpoint}`;

  try {
    const response = await fetch(url, config);

    // Handle 401 Unauthorized
    if (response.status === 401 && requireAuth) {
      localStorage.clear();
      window.location.href = '/';
      throw new Error('Session expired. Please login again.');
    }

    return response;
  } catch (error) {
    console.error('API Fetch Error:', error);
    throw error;
  }
}

/**
 * Refresh access token using refresh token
 */
export async function refreshAccessToken(): Promise<string | null> {
  try {
    const refreshToken = localStorage.getItem('refreshToken');
    
    if (!refreshToken) {
      return null;
    }

    const response = await fetch(`/api/auth/refresh/`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ refresh: refreshToken }),
    });

    if (response.ok) {
      const data = await response.json();
      localStorage.setItem('accessToken', data.access);
      return data.access;
    }

    return null;
  } catch (error) {
    console.error('Token refresh failed:', error);
    return null;
  }
}

/**
 * API helper methods
 */
export const api = {
  // GET request
  get: async (endpoint: string, requireAuth = true) => {
    const response = await apiFetch(endpoint, {
      method: 'GET',
      requireAuth,
    });
    
    if (!response.ok) {
      throw new Error(`GET ${endpoint} failed: ${response.statusText}`);
    }
    
    return response.json();
  },

  // POST request
  post: async (endpoint: string, data: any, requireAuth = true) => {
    const response = await apiFetch(endpoint, {
      method: 'POST',
      requireAuth,
      body: JSON.stringify(data),
    });
    
    if (!response.ok) {
      const errorData = await response.json().catch(() => ({}));
      throw new Error(errorData.error || `POST ${endpoint} failed`);
    }
    
    return response.json();
  },

  // PUT request
  put: async (endpoint: string, data: any, requireAuth = true) => {
    const response = await apiFetch(endpoint, {
      method: 'PUT',
      requireAuth,
      body: JSON.stringify(data),
    });
    
    if (!response.ok) {
      const errorData = await response.json().catch(() => ({}));
      throw new Error(errorData.error || `PUT ${endpoint} failed`);
    }
    
    return response.json();
  },

  // DELETE request
  delete: async (endpoint: string, requireAuth = true) => {
    const response = await apiFetch(endpoint, {
      method: 'DELETE',
      requireAuth,
    });
    
    if (!response.ok) {
      throw new Error(`DELETE ${endpoint} failed: ${response.statusText}`);
    }
    
    return response.json();
  },

  // File upload (multipart/form-data)
  upload: async (endpoint: string, formData: FormData, requireAuth = true) => {
    const token = localStorage.getItem('accessToken');
    
    if (requireAuth && !token) {
      window.location.href = '/';
      throw new Error('No authentication token found');
    }

    const headers: HeadersInit = {};
    if (requireAuth) {
      headers.Authorization = `Bearer ${token}`;
    }

    const response = await fetch(endpoint, {
      method: 'POST',
      headers,
      body: formData,
    });

    if (response.status === 401 && requireAuth) {
      localStorage.clear();
      window.location.href = '/';
      throw new Error('Session expired');
    }

    if (!response.ok) {
      throw new Error(`Upload failed: ${response.statusText}`);
    }

    return response.json();
  },
};

/**
 * Specific API endpoints
 */
export const endpoints = {
  // Auth
  login: '/api/auth/login/',
  logout: '/api/auth/logout/',
  refresh: '/api/auth/refresh/',
  me: '/api/me/',
  changePassword: '/api/auth/password/change/',
  forgotPassword: '/api/auth/password/forgot/',

  // Employees
  employees: '/api/employees/',
  employeeDetail: (id: number) => `/api/employees/${id}/`,
  employeeClients: (id: number) => `/api/employees/${id}/clients/`,
  employeeSales: (id: number) => `/api/employees/${id}/sales/`,

  // Sales
  sales: '/api/sales/',
  createSale: '/api/sales/create/',
  updateSale: (id: number) => `/api/sales/${id}/update/`,
  deleteSale: (id: number) => `/api/sales/${id}/delete/`,

  // Interactions
  interactions: '/api/interactions/',
  createInteraction: '/api/interactions/create/',
  updateInteraction: (id: number) => `/api/interactions/${id}/update/`,
  deleteInteraction: (id: number) => `/api/interactions/${id}/delete/`,

  // Export
  exportSales: '/api/export/sales/',
  exportSalesFiltered: '/api/export/sales/filtered/',
  exportInteractions: '/api/export/interactions/',
  exportInteractionsFiltered: '/api/export/interactions/filtered/',

  // Import
  importSales: '/api/import/sales/',
  importInteractions: '/api/import/interactions/',
};
