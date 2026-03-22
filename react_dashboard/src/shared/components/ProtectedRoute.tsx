import { Navigate } from 'react-router-dom';
import { useAuthStore } from '@/features/auth/store/authStore';
import React from 'react';

export default function ProtectedRoute({ children, requireAdmin = false }: { children: React.ReactNode, requireAdmin?: boolean }) {
  const { token, getIsAdmin } = useAuthStore();
  
  if (!token) return <Navigate to="/login" replace />;
  if (requireAdmin && !getIsAdmin()) return <Navigate to="/students" replace />;
  
  return <>{children}</>;
}
