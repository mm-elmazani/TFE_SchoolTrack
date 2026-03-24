import axios, { type AxiosError, type InternalAxiosRequestConfig } from 'axios';
import { useAuthStore } from '../features/auth/store/authStore';

const API_URL = import.meta.env.VITE_API_URL || 'http://localhost:8000';

export const apiClient = axios.create({
  baseURL: API_URL,
  headers: {
    'Content-Type': 'application/json',
  },
});

// Injecte le token JWT dans chaque requete
apiClient.interceptors.request.use((config) => {
  const token = useAuthStore.getState().token;
  if (token && config.headers) {
    config.headers.Authorization = `Bearer ${token}`;
  }
  return config;
});

// --- Intercepteur 401 : refresh token + replay requete ---

let isRefreshing = false;
let pendingRequests: Array<{
  resolve: (token: string) => void;
  reject: (err: unknown) => void;
}> = [];

function onRefreshSuccess(newToken: string) {
  pendingRequests.forEach(({ resolve }) => resolve(newToken));
  pendingRequests = [];
}

function onRefreshFailure(err: unknown) {
  pendingRequests.forEach(({ reject }) => reject(err));
  pendingRequests = [];
}

apiClient.interceptors.response.use(
  (response) => response,
  async (error: AxiosError) => {
    const originalRequest = error.config as InternalAxiosRequestConfig & { _retry?: boolean };

    // Ne pas intercepter les appels login/refresh eux-memes
    if (
      !originalRequest ||
      originalRequest._retry ||
      originalRequest.url?.includes('/auth/login') ||
      originalRequest.url?.includes('/auth/refresh')
    ) {
      return Promise.reject(error);
    }

    if (error.response?.status !== 401) {
      return Promise.reject(error);
    }

    // Un refresh est deja en cours — mettre la requete en file d'attente
    if (isRefreshing) {
      return new Promise<string>((resolve, reject) => {
        pendingRequests.push({ resolve, reject });
      }).then((newToken) => {
        originalRequest.headers.Authorization = `Bearer ${newToken}`;
        originalRequest._retry = true;
        return apiClient(originalRequest);
      });
    }

    isRefreshing = true;
    originalRequest._retry = true;

    const { refreshToken, setTokens, logout } = useAuthStore.getState();

    if (!refreshToken) {
      isRefreshing = false;
      logout();
      window.location.href = '/login';
      return Promise.reject(error);
    }

    try {
      const response = await axios.post(`${API_URL}/api/v1/auth/refresh`, {
        refresh_token: refreshToken,
      });

      const { access_token, refresh_token: newRefreshToken } = response.data;
      setTokens(access_token, newRefreshToken);

      // Rejouer la requete originale + debloquer les requetes en attente
      originalRequest.headers.Authorization = `Bearer ${access_token}`;
      onRefreshSuccess(access_token);

      return apiClient(originalRequest);
    } catch (refreshError) {
      onRefreshFailure(refreshError);
      logout();
      window.location.href = '/login';
      return Promise.reject(refreshError);
    } finally {
      isRefreshing = false;
    }
  }
);
