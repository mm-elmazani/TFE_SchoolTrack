import { createBrowserRouter } from 'react-router-dom';
import AppScaffold from '@/shared/components/AppScaffold';
import ProtectedRoute from '@/shared/components/ProtectedRoute';
import LoginScreen from '@/features/auth/screens/LoginScreen';
import DashboardScreen from '@/features/dashboard/screens/DashboardScreen';
import StudentListScreen from '@/features/students/screens/StudentListScreen';
import StudentDetailScreen from '@/features/students/screens/StudentDetailScreen';
import StudentImportScreen from '@/features/students/screens/StudentImportScreen';
import TripListScreen from '@/features/trips/screens/TripListScreen';
import TripDetailScreen from '@/features/trips/screens/TripDetailScreen';
import ClassListScreen from '@/features/classes/screens/ClassListScreen';
import ClassDetailScreen from '@/features/classes/screens/ClassDetailScreen';
import UserListScreen from '@/features/users/screens/UserListScreen';
import AuditLogScreen from '@/features/audit/screens/AuditLogScreen';
import TokenManagementScreen from '@/features/tokens/screens/TokenManagementScreen';
import TokenStockScreen from '@/features/tokens/screens/TokenStockScreen';

export const router = createBrowserRouter([
  {
    path: '/login',
    element: <LoginScreen />,
  },
  {
    path: '/',
    element: (
      <ProtectedRoute>
        <AppScaffold />
      </ProtectedRoute>
    ),
    children: [
      {
        path: '',
        element: <DashboardScreen />,
      },
      {
        path: 'students/import',
        element: (
          <ProtectedRoute requireAdmin>
            <StudentImportScreen />
          </ProtectedRoute>
        ),
      },
      {
        path: 'students',
        element: <StudentListScreen />,
      },
      {
        path: 'students/:id',
        element: <StudentDetailScreen />,
      },
      {
        path: 'trips',
        element: <TripListScreen />,
      },
      {
        path: 'trips/:id',
        element: <TripDetailScreen />,
      },
      {
        path: 'classes',
        element: <ClassListScreen />,
      },
      {
        path: 'classes/:id',
        element: <ClassDetailScreen />,
      },
      {
        path: 'users',
        element: (
          <ProtectedRoute requireAdmin>
            <UserListScreen />
          </ProtectedRoute>
        ),
      },
      {
        path: 'audit',
        element: (
          <ProtectedRoute requireAdmin>
            <AuditLogScreen />
          </ProtectedRoute>
        ),
      },
      {
        path: 'tokens',
        element: <TokenManagementScreen />,
      },
      {
        path: 'tokens/stock',
        element: (
          <ProtectedRoute requireAdmin>
            <TokenStockScreen />
          </ProtectedRoute>
        ),
      },
    ],
  },
]);

