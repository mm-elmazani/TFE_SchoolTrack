import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen } from '../../../test/test-utils';
import DashboardScreen from '../screens/DashboardScreen';
import { getDashboardOverview } from '../api/dashboardApi';

vi.mock('../api/dashboardApi', () => ({
  getDashboardOverview: vi.fn(),
}));

beforeEach(() => vi.clearAllMocks());

const mockOverview = {
  total_trips: 2,
  active_trips: 2,
  planned_trips: 3,
  completed_trips: 0,
  total_students: 50,
  total_attendances: 19,
  global_attendance_rate: 95.5,
  scan_method_stats: { nfc: 10, qr_physical: 5, qr_digital: 3, manual: 1, total: 19 },
  trips: [] as any[],
  generated_at: '2026-01-01T00:00:00Z',
};

describe('DashboardScreen', () => {
  it('renders error state with retry button', async () => {
    vi.mocked(getDashboardOverview).mockRejectedValue(new Error('Erreur serveur'));
    render(<DashboardScreen />);
    expect(await screen.findByText(/Reessayer/, {}, { timeout: 5000 })).toBeInTheDocument();
  });

  it('renders dashboard data with stats cards', async () => {
    vi.mocked(getDashboardOverview).mockResolvedValue(mockOverview);
    render(<DashboardScreen />);
    expect(await screen.findByText('50')).toBeInTheDocument();
    expect(screen.getByText('Voyages actifs')).toBeInTheDocument();
    expect(screen.getByText('Total eleves')).toBeInTheDocument();
    expect(screen.getAllByText('Taux presence global').length).toBeGreaterThan(0);
  });

  it('renders empty trip list message', async () => {
    vi.mocked(getDashboardOverview).mockResolvedValue(mockOverview);
    render(<DashboardScreen />);
    expect(await screen.findByText(/Aucun voyage/)).toBeInTheDocument();
  });

  it('renders scan method chart', async () => {
    vi.mocked(getDashboardOverview).mockResolvedValue(mockOverview);
    render(<DashboardScreen />);
    expect(await screen.findByText('Modes de scan')).toBeInTheDocument();
  });

  it('renders summary section', async () => {
    vi.mocked(getDashboardOverview).mockResolvedValue(mockOverview);
    render(<DashboardScreen />);
    expect(await screen.findByText('Resume')).toBeInTheDocument();
    expect(screen.getByText('Total voyages')).toBeInTheDocument();
  });

  it('renders trip cards when trips exist', async () => {
    vi.mocked(getDashboardOverview).mockResolvedValue({
      ...mockOverview,
      trips: [{
        id: 't1', destination: 'Bruges', date: '2026-06-15', status: 'ACTIVE',
        total_students: 25, total_present: 20, attendance_rate: 80,
        total_checkpoints: 2, closed_checkpoints: 1,
        last_checkpoint: null, checkpoints: [],
      }],
    });
    render(<DashboardScreen />);
    expect(await screen.findByText('Bruges')).toBeInTheDocument();
    expect(screen.getByText('En cours')).toBeInTheDocument();
  });

  it('renders filter and subtitle', async () => {
    vi.mocked(getDashboardOverview).mockResolvedValue(mockOverview);
    render(<DashboardScreen />);
    expect(await screen.findByText(/Statistiques et suivi/)).toBeInTheDocument();
  });
});
