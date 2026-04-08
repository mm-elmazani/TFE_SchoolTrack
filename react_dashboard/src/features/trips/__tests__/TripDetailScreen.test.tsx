import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, fireEvent } from '../../../test/test-utils';
import userEvent from '@testing-library/user-event';
import TripDetailScreen from '../screens/TripDetailScreen';
import { tripApi } from '../api/tripApi';
import { useAuthStore } from '@/features/auth/store/authStore';

vi.mock('../api/tripApi', () => ({
  tripApi: { getById: vi.fn(), getCheckpointsSummary: vi.fn() },
}));

vi.mock('../components/UpdateTripDialog', () => ({
  UpdateTripDialog: () => null,
}));

vi.mock('react-router-dom', async () => {
  const actual = await vi.importActual('react-router-dom');
  return { ...actual, useParams: () => ({ id: 'trip-1', schoolSlug: 'dev' }) };
});

vi.mock('@/hooks/useSchoolPath', () => ({
  useSchoolPath: () => (path: string) => `/dev${path}`,
}));

const mockTrip = {
  id: 'trip-1', destination: 'Bruges', date: '2026-06-15', status: 'ACTIVE',
  classes: [], total_students: 25, description: 'Excursion culturelle',
  created_at: '2026-01-01', updated_at: '2026-01-01',
};

const mockCheckpointsSummary = {
  total_checkpoints: 2,
  total_scans: 45,
  timeline: [
    { id: 'cp1', name: 'Départ', status: 'CLOSED', scanned_count: 24, total_count: 25, created_at: '2026-06-15T08:00:00Z' },
    { id: 'cp2', name: 'Arrivée', status: 'OPEN', scanned_count: 20, total_count: 25, created_at: '2026-06-15T10:00:00Z' },
  ],
};

beforeEach(() => {
  vi.clearAllMocks();
  useAuthStore.setState({
    token: 'test',
    user: { id: '1', email: 'admin@test.be', first_name: 'Admin', last_name: 'Test', role: 'DIRECTION' },
  });
});

describe('TripDetailScreen', () => {
  it('renders loading state', () => {
    vi.mocked(tripApi.getById).mockReturnValue(new Promise(() => {}));
    vi.mocked(tripApi.getCheckpointsSummary).mockReturnValue(new Promise(() => {}));
    render(<TripDetailScreen />);
    expect(document.querySelector('.animate-spin')).toBeTruthy();
  });

  it('renders error state', async () => {
    vi.mocked(tripApi.getById).mockRejectedValue(new Error('Not found'));
    vi.mocked(tripApi.getCheckpointsSummary).mockResolvedValue([]);
    render(<TripDetailScreen />);
    expect(await screen.findByText('Voyage introuvable')).toBeInTheDocument();
  });

  it('renders back link on error', async () => {
    vi.mocked(tripApi.getById).mockRejectedValue(new Error('Not found'));
    vi.mocked(tripApi.getCheckpointsSummary).mockResolvedValue([]);
    render(<TripDetailScreen />);
    await screen.findByText('Voyage introuvable');
    expect(screen.getByText(/Retour à la liste/i)).toBeInTheDocument();
  });

  it('renders trip destination', async () => {
    vi.mocked(tripApi.getById).mockResolvedValue(mockTrip as any);
    vi.mocked(tripApi.getCheckpointsSummary).mockResolvedValue(mockCheckpointsSummary as any);
    render(<TripDetailScreen />);
    expect(await screen.findByText('Bruges')).toBeInTheDocument();
  });

  it('renders ACTIVE status badge', async () => {
    vi.mocked(tripApi.getById).mockResolvedValue(mockTrip as any);
    vi.mocked(tripApi.getCheckpointsSummary).mockResolvedValue(mockCheckpointsSummary as any);
    render(<TripDetailScreen />);
    expect(await screen.findByText(/En cours/i)).toBeInTheDocument();
  });

  it('renders PLANNED status badge', async () => {
    vi.mocked(tripApi.getById).mockResolvedValue({ ...mockTrip, status: 'PLANNED' } as any);
    vi.mocked(tripApi.getCheckpointsSummary).mockResolvedValue([] as any);
    render(<TripDetailScreen />);
    expect(await screen.findByText(/À venir/i)).toBeInTheDocument();
  });

  it('renders COMPLETED status badge', async () => {
    vi.mocked(tripApi.getById).mockResolvedValue({ ...mockTrip, status: 'COMPLETED' } as any);
    vi.mocked(tripApi.getCheckpointsSummary).mockResolvedValue([] as any);
    render(<TripDetailScreen />);
    expect(await screen.findByText(/Terminé/i)).toBeInTheDocument();
  });

  it('renders ARCHIVED status badge', async () => {
    vi.mocked(tripApi.getById).mockResolvedValue({ ...mockTrip, status: 'ARCHIVED' } as any);
    vi.mocked(tripApi.getCheckpointsSummary).mockResolvedValue([] as any);
    render(<TripDetailScreen />);
    expect(await screen.findByText(/Archivé/i)).toBeInTheDocument();
  });

  it('renders student count', async () => {
    vi.mocked(tripApi.getById).mockResolvedValue(mockTrip as any);
    vi.mocked(tripApi.getCheckpointsSummary).mockResolvedValue([] as any);
    render(<TripDetailScreen />);
    expect(await screen.findByText(/25 élèves inscrits/i)).toBeInTheDocument();
  });

  it('renders empty classes message', async () => {
    vi.mocked(tripApi.getById).mockResolvedValue(mockTrip as any);
    vi.mocked(tripApi.getCheckpointsSummary).mockResolvedValue([] as any);
    render(<TripDetailScreen />);
    expect(await screen.findByText(/Aucune classe n'est assignée/i)).toBeInTheDocument();
  });

  it('renders classes when trip has classes', async () => {
    vi.mocked(tripApi.getById).mockResolvedValue({
      ...mockTrip,
      classes: [
        { id: 'c1', name: '5ème A', year: '2025-2026', student_count: 20 },
      ],
    } as any);
    vi.mocked(tripApi.getCheckpointsSummary).mockResolvedValue([] as any);
    render(<TripDetailScreen />);
    expect(await screen.findByText('5ème A')).toBeInTheDocument();
    expect(screen.getByText('2025-2026')).toBeInTheDocument();
    expect(screen.getByText(/20 élèves/i)).toBeInTheDocument();
  });

  it('renders checkpoints tab content after click', async () => {
    vi.mocked(tripApi.getById).mockResolvedValue(mockTrip as any);
    vi.mocked(tripApi.getCheckpointsSummary).mockResolvedValue([] as any);
    const user = userEvent.setup();
    render(<TripDetailScreen />);
    await screen.findByText('Bruges');
    await user.click(screen.getByText('Points de contrôle'));
    expect(await screen.findByText(/Aucun checkpoint enregistré/i)).toBeInTheDocument();
  });

  it('renders checkpoints timeline when available', async () => {
    vi.mocked(tripApi.getById).mockResolvedValue(mockTrip as any);
    vi.mocked(tripApi.getCheckpointsSummary).mockResolvedValue(mockCheckpointsSummary as any);
    const user = userEvent.setup();
    render(<TripDetailScreen />);
    await screen.findByText('Bruges');
    await user.click(screen.getByText('Points de contrôle'));
    expect(await screen.findByText('Départ')).toBeInTheDocument();
    expect(await screen.findByText('Arrivée')).toBeInTheDocument();
  });

  it('renders Modifier le voyage button for admin on non-archived trip', async () => {
    vi.mocked(tripApi.getById).mockResolvedValue(mockTrip as any);
    vi.mocked(tripApi.getCheckpointsSummary).mockResolvedValue([] as any);
    render(<TripDetailScreen />);
    expect(await screen.findByText(/Modifier le voyage/i)).toBeInTheDocument();
  });

  it('does not render Modifier button for archived trip', async () => {
    vi.mocked(tripApi.getById).mockResolvedValue({ ...mockTrip, status: 'ARCHIVED' } as any);
    vi.mocked(tripApi.getCheckpointsSummary).mockResolvedValue([] as any);
    render(<TripDetailScreen />);
    await screen.findByText(/Archivé/i);
    expect(screen.queryByText(/Modifier le voyage/i)).not.toBeInTheDocument();
  });

  it('renders Classes inscrites tab header', async () => {
    vi.mocked(tripApi.getById).mockResolvedValue(mockTrip as any);
    vi.mocked(tripApi.getCheckpointsSummary).mockResolvedValue([] as any);
    render(<TripDetailScreen />);
    expect(await screen.findByText('Classes inscrites')).toBeInTheDocument();
  });
});
