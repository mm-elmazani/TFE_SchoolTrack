import { create } from 'zustand';
import { persist } from 'zustand/middleware';

export interface User {
  id: string;
  email: string;
  role: 'DIRECTION' | 'TEACHER' | 'OBSERVER' | 'ADMIN_TECH';
  first_name?: string;
  last_name?: string;
}

interface AuthState {
  token: string | null;
  user: User | null;
  setAuth: (token: string, user: User) => void;
  logout: () => void;
  getIsAdmin: () => boolean; // Can manage users/audit/etc. (DIRECTION, ADMIN_TECH)
  getCanManageStudents: () => boolean; // DIRECTION, ADMIN_TECH, TEACHER
}

export const useAuthStore = create<AuthState>()(
  persist(
    (set, get) => ({
      token: null,
      user: null,
      setAuth: (token, user) => set({ token, user }),
      logout: () => set({ token: null, user: null }),
      getIsAdmin: () => {
        const role = get().user?.role;
        return role === 'DIRECTION' || role === 'ADMIN_TECH';
      },
      getCanManageStudents: () => {
        const role = get().user?.role;
        return role === 'DIRECTION' || role === 'ADMIN_TECH' || role === 'TEACHER';
      },
    }),
    {
      name: 'schooltrack-auth-storage',
    }
  )
);
