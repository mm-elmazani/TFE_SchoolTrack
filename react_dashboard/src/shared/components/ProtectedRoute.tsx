import { Navigate, useParams } from 'react-router-dom';
import { useAuthStore } from '@/features/auth/store/authStore';
import React from 'react';

export default function ProtectedRoute({ children, requireAdmin = false }: { children: React.ReactNode, requireAdmin?: boolean }) {
  const { token, user, getIsAdmin } = useAuthStore();
  const { schoolSlug } = useParams();
  const slug = schoolSlug || user?.school_slug || '';

  if (!token) return <Navigate to={`/${slug}/login`} replace />;
  if (requireAdmin && !getIsAdmin()) return <Navigate to={`/${slug}/students`} replace />;

  return <>{children}</>;
}
