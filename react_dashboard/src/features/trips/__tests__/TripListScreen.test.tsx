import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '../../../test/test-utils';
import TripListScreen from '../screens/TripListScreen';
import { tripApi } from '../api/tripApi';

// Mock API
vi.mock('../api/tripApi', () => ({
  tripApi: {
    getAll: vi.fn(),
  },
}));

describe('TripListScreen', () => {
  it('renders loading state initially', () => {
    vi.mocked(tripApi.getAll).mockReturnValue(new Promise(() => {}));
    render(<TripListScreen />);
    expect(screen.getByText('Chargement des voyages...')).toBeInTheDocument();
  });

  it('renders error state', async () => {
    vi.mocked(tripApi.getAll).mockRejectedValue(new Error('API Error'));
    render(<TripListScreen />);
    expect(await screen.findByText('Erreur de chargement')).toBeInTheDocument();
  });

  it('renders a list of trips', async () => {
    const mockTrips = [
      { id: '1', destination: 'Paris', date: '2026-05-10', description: 'Test', status: 'PLANNED', total_students: 10, classes: [], created_at: '', updated_at: '' },
    ] as any;
    vi.mocked(tripApi.getAll).mockResolvedValue(mockTrips);

    render(<TripListScreen />);
    
    expect(await screen.findByText('Paris')).toBeInTheDocument();
    expect(screen.getAllByText(/À venir/i).length).toBeGreaterThan(0);
  });
});
