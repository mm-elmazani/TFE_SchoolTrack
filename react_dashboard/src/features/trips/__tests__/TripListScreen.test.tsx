import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen } from '../../../test/test-utils';
import TripListScreen from '../screens/TripListScreen';
import { tripApi } from '../api/tripApi';
import { useAuthStore } from '@/features/auth/store/authStore';

vi.mock('../api/tripApi', () => ({
  tripApi: { getAll: vi.fn(), getExportUrl: vi.fn(() => '/export'), getBulkExportUrl: vi.fn(() => '/bulk-export') },
}));

vi.mock('../components/CreateTripDialog', () => ({
  CreateTripDialog: () => null,
}));
vi.mock('../components/UpdateTripDialog', () => ({
  UpdateTripDialog: () => null,
}));
vi.mock('../components/ArchiveTripDialog', () => ({
  ArchiveTripDialog: () => null,
}));

const mockTrips = [
  { id: '1', destination: 'Paris', date: '2026-05-10', description: 'Voyage culturel', status: 'PLANNED', total_students: 25, classes: [], created_at: '', updated_at: '' },
  { id: '2', destination: 'Bruges', date: '2026-04-01', description: 'Excursion historique', status: 'ACTIVE', total_students: 30, classes: [], created_at: '', updated_at: '' },
  { id: '3', destination: 'Gand', date: '2025-12-15', description: 'Termine', status: 'COMPLETED', total_students: 20, classes: [], created_at: '', updated_at: '' },
] as any;

beforeEach(() => {
  vi.clearAllMocks();
  useAuthStore.setState({
    token: 'test',
    user: { id: '1', email: 'admin@test.be', first_name: 'Admin', last_name: 'Test', role: 'DIRECTION' },
  });
});

describe('TripListScreen', () => {
  it('renders loading state', () => {
    vi.mocked(tripApi.getAll).mockReturnValue(new Promise(() => {}));
    render(<TripListScreen />);
    expect(screen.getByText('Chargement des voyages...')).toBeInTheDocument();
  });

  it('renders error state', async () => {
    vi.mocked(tripApi.getAll).mockRejectedValue(new Error('API Error'));
    render(<TripListScreen />);
    expect(await screen.findByText('Erreur de chargement')).toBeInTheDocument();
    expect(screen.getByText(/Impossible de r.*la liste des voyages/i)).toBeInTheDocument();
  });

  it('renders page title and subtitle', async () => {
    vi.mocked(tripApi.getAll).mockResolvedValue(mockTrips);
    render(<TripListScreen />);
    expect(await screen.findByText('Voyages')).toBeInTheDocument();
    expect(screen.getByText(/Planifiez.*suivez/i)).toBeInTheDocument();
  });

  it('renders trip cards in grid view', async () => {
    vi.mocked(tripApi.getAll).mockResolvedValue(mockTrips);
    render(<TripListScreen />);
    expect(await screen.findByText('Paris')).toBeInTheDocument();
    expect(screen.getByText('Bruges')).toBeInTheDocument();
    expect(screen.getByText('Gand')).toBeInTheDocument();
  });

  it('renders status badges', async () => {
    vi.mocked(tripApi.getAll).mockResolvedValue(mockTrips);
    render(<TripListScreen />);
    await screen.findByText('Paris');
    expect(screen.getAllByText(/venir/i).length).toBeGreaterThan(0);
    expect(screen.getAllByText(/En cours/i).length).toBeGreaterThan(0);
    expect(screen.getAllByText(/Termin/i).length).toBeGreaterThan(0);
  });

  it('renders stats summary cards', async () => {
    vi.mocked(tripApi.getAll).mockResolvedValue(mockTrips);
    render(<TripListScreen />);
    await screen.findByText('Paris');
    // 1 active, 1 upcoming, 1 completed
    const statValues = screen.getAllByText('1');
    expect(statValues.length).toBeGreaterThan(0);
  });

  it('renders empty state when no trips match', async () => {
    vi.mocked(tripApi.getAll).mockResolvedValue([]);
    render(<TripListScreen />);
    expect(await screen.findByText(/Aucun voyage trouv/i)).toBeInTheDocument();
  });

  it('renders search bar', async () => {
    vi.mocked(tripApi.getAll).mockResolvedValue(mockTrips);
    render(<TripListScreen />);
    await screen.findByText('Paris');
    expect(screen.getByPlaceholderText(/Rechercher une destination/i)).toBeInTheDocument();
  });

  it('renders new trip button for admin', async () => {
    vi.mocked(tripApi.getAll).mockResolvedValue(mockTrips);
    render(<TripListScreen />);
    await screen.findByText('Paris');
    expect(screen.getByText('Nouveau Voyage')).toBeInTheDocument();
  });

  it('renders trip descriptions', async () => {
    vi.mocked(tripApi.getAll).mockResolvedValue(mockTrips);
    render(<TripListScreen />);
    expect(await screen.findByText('Voyage culturel')).toBeInTheDocument();
    expect(screen.getByText('Excursion historique')).toBeInTheDocument();
  });

  it('renders view mode toggle', async () => {
    vi.mocked(tripApi.getAll).mockResolvedValue(mockTrips);
    render(<TripListScreen />);
    await screen.findByText('Paris');
    expect(screen.getByText('Grille')).toBeInTheDocument();
    expect(screen.getByText('Liste')).toBeInTheDocument();
  });

  it('renders retry button on error', async () => {
    vi.mocked(tripApi.getAll).mockRejectedValue(new Error('fail'));
    render(<TripListScreen />);
    expect(await screen.findByText(/essayer/i)).toBeInTheDocument();
  });

  it('renders detail links for trips', async () => {
    vi.mocked(tripApi.getAll).mockResolvedValue(mockTrips);
    render(<TripListScreen />);
    await screen.findByText('Paris');
    expect(screen.getAllByText(/tail/i).length).toBeGreaterThan(0);
  });
});
