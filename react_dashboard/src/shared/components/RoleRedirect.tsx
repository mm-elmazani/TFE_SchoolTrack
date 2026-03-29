import { Navigate, useParams } from 'react-router-dom';
import { useAuthStore } from '@/features/auth/store/authStore';

export default function RoleRedirect() {
  const isAdmin = useAuthStore(s => s.getIsAdmin());
  const { schoolSlug } = useParams();
  return <Navigate to={isAdmin ? `/${schoolSlug}/dashboard` : `/${schoolSlug}/students`} replace />;
}
