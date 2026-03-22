import { Navigate } from 'react-router-dom';
import { useAuthStore } from '@/features/auth/store/authStore';

export default function RoleRedirect() {
  const isAdmin = useAuthStore(s => s.getIsAdmin());
  return <Navigate to={isAdmin ? '/dashboard' : '/students'} replace />;
}
