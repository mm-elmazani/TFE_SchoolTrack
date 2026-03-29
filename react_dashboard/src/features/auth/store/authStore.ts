import { create } from 'zustand';
import { persist } from 'zustand/middleware';

export interface User {
  id: string;
  email: string;
  role: 'DIRECTION' | 'TEACHER' | 'OBSERVER' | 'ADMIN_TECH';
  first_name?: string;
  last_name?: string;
  is_2fa_enabled?: boolean;
  two_fa_method?: string | null;
  school_slug?: string;
}

interface AuthState {
  token: string | null;
  refreshToken: string | null;
  user: User | null;
  setAuth: (token: string, refreshToken: string, user: User) => void;
  setTokens: (token: string, refreshToken: string) => void;
  updateUser: (patch: Partial<User>) => void;
  logout: () => void;
  getIsAdmin: () => boolean;
  getCanManageStudents: () => boolean;
  getIsObserver: () => boolean;
}

export const useAuthStore = create<AuthState>()(
  persist(
    (set, get) => ({
      token: null,
      refreshToken: null,
      user: null,
      setAuth: (token, refreshToken, user) => set({ token, refreshToken, user }),
      setTokens: (token, refreshToken) => set({ token, refreshToken }),
      updateUser: (patch) => set((state) => ({ user: state.user ? { ...state.user, ...patch } : null })),
      logout: () => set({ token: null, refreshToken: null, user: null }),
      getIsAdmin: () => {
        const role = get().user?.role;
        return role === 'DIRECTION' || role === 'ADMIN_TECH';
      },
      getCanManageStudents: () => {
        const role = get().user?.role;
        return role === 'DIRECTION' || role === 'ADMIN_TECH' || role === 'TEACHER';
      },
      getIsObserver: () => {
        return get().user?.role === 'OBSERVER';
      },
    }),
    {
      name: 'schooltrack-auth-storage',
    }
  )
);
