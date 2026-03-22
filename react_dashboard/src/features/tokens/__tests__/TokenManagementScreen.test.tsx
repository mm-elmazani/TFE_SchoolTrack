import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '../../../test/test-utils';
import TokenManagementScreen from '../screens/TokenManagementScreen';
import { tripApi } from '@/features/trips/api/tripApi';

// Mock API
vi.mock('@/features/trips/api/tripApi', () => ({
  tripApi: {
    getAll: vi.fn(),
  },
}));

vi.mock('../api/tokenApi', () => ({
  tokenApi: {
    getTripAssignmentsStatus: vi.fn(),
  },
}));

describe('TokenManagementScreen', () => {
  it('renders empty state if no trips are selected', async () => {
    vi.mocked(tripApi.getAll).mockResolvedValue([
      { id: '1', destination: 'Paris', date: '2026-05-10', description: 'Test', status: 'ACTIVE', total_students: 10, classes: [], created_at: '', updated_at: '' } as any
    ]);
    
    render(<TokenManagementScreen />);
    
    expect(await screen.findByText('Paris')).toBeInTheDocument();
    expect(screen.getByText(/Sélectionnez un voyage/i)).toBeInTheDocument();
  });
});
