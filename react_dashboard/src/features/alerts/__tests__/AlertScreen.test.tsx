import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, fireEvent } from '../../../test/test-utils';
import AlertScreen from '../screens/AlertScreen';
import { getAlerts, getAlertStats, updateAlertStatus } from '../api/alertApi';

vi.mock('../api/alertApi', () => ({
  getAlerts: vi.fn(),
  getAlertStats: vi.fn(),
  updateAlertStatus: vi.fn(),
}));

const mockStats = { active: 2, in_progress: 1, resolved: 5, critical_count: 1 };

const mockAlerts = [
  {
    id: 'alert-1', trip_id: 't1', student_id: 's1',
    student_name: 'Dupont Marie', trip_destination: 'Bruges',
    alert_type: 'STUDENT_MISSING', severity: 'HIGH', message: 'Absent au checkpoint',
    status: 'ACTIVE', created_at: '2026-06-15T10:00:00Z',
  },
  {
    id: 'alert-2', trip_id: 't2', student_id: 's2',
    student_name: 'Martin Jean', trip_destination: 'Paris',
    alert_type: 'CHECKPOINT_DELAYED', severity: 'CRITICAL', message: 'Retard important',
    status: 'IN_PROGRESS', created_at: '2026-06-15T09:00:00Z',
  },
];

beforeEach(() => {
  vi.clearAllMocks();
});

describe('AlertScreen', () => {
  it('renders loading state initially', () => {
    vi.mocked(getAlerts).mockReturnValue(new Promise(() => {}));
    vi.mocked(getAlertStats).mockReturnValue(new Promise(() => {}));
    render(<AlertScreen />);
    expect(document.querySelector('.animate-spin')).toBeTruthy();
  });

  it('renders empty state', async () => {
    vi.mocked(getAlerts).mockResolvedValue([]);
    vi.mocked(getAlertStats).mockResolvedValue({ active: 0, in_progress: 0, resolved: 0, critical_count: 0 });
    render(<AlertScreen />);
    expect(await screen.findByText(/Aucune alerte/)).toBeInTheDocument();
  });

  it('renders alert cards with data', async () => {
    vi.mocked(getAlerts).mockResolvedValue(mockAlerts);
    vi.mocked(getAlertStats).mockResolvedValue(mockStats);
    render(<AlertScreen />);
    expect(await screen.findByText(/Dupont Marie/)).toBeInTheDocument();
    expect(screen.getByText(/Martin Jean/)).toBeInTheDocument();
  });

  it('renders subtitle text', async () => {
    vi.mocked(getAlerts).mockResolvedValue([]);
    vi.mocked(getAlertStats).mockResolvedValue({ active: 0, in_progress: 0, resolved: 0, critical_count: 0 });
    render(<AlertScreen />);
    expect(await screen.findByText(/Alertes temps r.el/i)).toBeInTheDocument();
  });

  it('renders stats cards', async () => {
    vi.mocked(getAlerts).mockResolvedValue(mockAlerts);
    vi.mocked(getAlertStats).mockResolvedValue(mockStats);
    render(<AlertScreen />);
    await screen.findByText(/Dupont Marie/);
    expect(screen.getAllByText(/Actives/i).length).toBeGreaterThan(0);
    expect(screen.getAllByText(/En cours/i).length).toBeGreaterThan(0);
    expect(screen.getAllByText(/R.solues/i).length).toBeGreaterThan(0);
    expect(screen.getAllByText(/Critiques/i).length).toBeGreaterThan(0);
  });

  it('renders stat values', async () => {
    vi.mocked(getAlerts).mockResolvedValue(mockAlerts);
    vi.mocked(getAlertStats).mockResolvedValue(mockStats);
    render(<AlertScreen />);
    await screen.findByText(/Dupont Marie/);
    expect(screen.getAllByText('2').length).toBeGreaterThan(0);
    expect(screen.getAllByText('5').length).toBeGreaterThan(0);
  });

  it('renders alert type label for STUDENT_MISSING', async () => {
    vi.mocked(getAlerts).mockResolvedValue(mockAlerts);
    vi.mocked(getAlertStats).mockResolvedValue(mockStats);
    render(<AlertScreen />);
    expect(await screen.findByText(/Eleve manquant/i)).toBeInTheDocument();
  });

  it('renders alert type label for CHECKPOINT_DELAYED', async () => {
    vi.mocked(getAlerts).mockResolvedValue(mockAlerts);
    vi.mocked(getAlertStats).mockResolvedValue(mockStats);
    render(<AlertScreen />);
    expect(await screen.findByText(/Checkpoint en retard/i)).toBeInTheDocument();
  });

  it('renders severity badge for HIGH', async () => {
    vi.mocked(getAlerts).mockResolvedValue(mockAlerts);
    vi.mocked(getAlertStats).mockResolvedValue(mockStats);
    render(<AlertScreen />);
    expect(await screen.findByText('Haute')).toBeInTheDocument();
  });

  it('renders severity badge for CRITICAL', async () => {
    vi.mocked(getAlerts).mockResolvedValue(mockAlerts);
    vi.mocked(getAlertStats).mockResolvedValue(mockStats);
    render(<AlertScreen />);
    expect(await screen.findByText('Critique')).toBeInTheDocument();
  });

  it('renders alert message text', async () => {
    vi.mocked(getAlerts).mockResolvedValue(mockAlerts);
    vi.mocked(getAlertStats).mockResolvedValue(mockStats);
    render(<AlertScreen />);
    expect(await screen.findByText('Absent au checkpoint')).toBeInTheDocument();
    expect(screen.getByText('Retard important')).toBeInTheDocument();
  });

  it('renders trip destinations', async () => {
    vi.mocked(getAlerts).mockResolvedValue(mockAlerts);
    vi.mocked(getAlertStats).mockResolvedValue(mockStats);
    render(<AlertScreen />);
    expect(await screen.findByText('Bruges')).toBeInTheDocument();
    expect(screen.getByText('Paris')).toBeInTheDocument();
  });

  it('renders status badge Active for ACTIVE alert', async () => {
    vi.mocked(getAlerts).mockResolvedValue(mockAlerts);
    vi.mocked(getAlertStats).mockResolvedValue(mockStats);
    render(<AlertScreen />);
    expect(await screen.findByText('Active')).toBeInTheDocument();
  });

  it('renders "Prendre en charge" button for ACTIVE alert', async () => {
    vi.mocked(getAlerts).mockResolvedValue(mockAlerts);
    vi.mocked(getAlertStats).mockResolvedValue(mockStats);
    render(<AlertScreen />);
    expect(await screen.findByText(/Prendre en charge/i)).toBeInTheDocument();
  });

  it('renders "Resoudre" button for IN_PROGRESS alert', async () => {
    vi.mocked(getAlerts).mockResolvedValue(mockAlerts);
    vi.mocked(getAlertStats).mockResolvedValue(mockStats);
    render(<AlertScreen />);
    expect(await screen.findAllByText(/Resoudre/i)).not.toHaveLength(0);
  });

  it('renders refresh button', async () => {
    vi.mocked(getAlerts).mockResolvedValue(mockAlerts);
    vi.mocked(getAlertStats).mockResolvedValue(mockStats);
    render(<AlertScreen />);
    await screen.findByText(/Dupont Marie/);
    const buttons = screen.getAllByRole('button');
    expect(buttons.length).toBeGreaterThan(0);
  });

  it('clicking Prendre en charge calls updateAlertStatus', async () => {
    vi.mocked(getAlerts).mockResolvedValue(mockAlerts);
    vi.mocked(getAlertStats).mockResolvedValue(mockStats);
    vi.mocked(updateAlertStatus).mockResolvedValue({} as any);
    render(<AlertScreen />);
    await screen.findByText(/Prendre en charge/i);
    fireEvent.click(screen.getByText(/Prendre en charge/i));
    expect(screen.getByText(/Dupont Marie/)).toBeInTheDocument();
  });

  it('clicking Resoudre calls updateAlertStatus', async () => {
    vi.mocked(getAlerts).mockResolvedValue(mockAlerts);
    vi.mocked(getAlertStats).mockResolvedValue(mockStats);
    vi.mocked(updateAlertStatus).mockResolvedValue({} as any);
    render(<AlertScreen />);
    const resolveButtons = await screen.findAllByText(/Resoudre/i);
    fireEvent.click(resolveButtons[0]);
    expect(screen.getByText(/Dupont Marie/)).toBeInTheDocument();
  });

  it('renders SYNC_FAILED alert type label', async () => {
    vi.mocked(getAlerts).mockResolvedValue([{
      ...mockAlerts[0], alert_type: 'SYNC_FAILED', severity: 'MEDIUM', status: 'RESOLVED',
    }]);
    vi.mocked(getAlertStats).mockResolvedValue(mockStats);
    render(<AlertScreen />);
    expect(await screen.findByText(/Echec synchronisation/i)).toBeInTheDocument();
  });

  it('renders Moyenne severity badge', async () => {
    vi.mocked(getAlerts).mockResolvedValue([{
      ...mockAlerts[0], severity: 'MEDIUM', status: 'RESOLVED',
    }]);
    vi.mocked(getAlertStats).mockResolvedValue(mockStats);
    render(<AlertScreen />);
    expect(await screen.findByText('Moyenne')).toBeInTheDocument();
  });

  it('renders Resolue status badge', async () => {
    vi.mocked(getAlerts).mockResolvedValue([{
      ...mockAlerts[0], status: 'RESOLVED',
    }]);
    vi.mocked(getAlertStats).mockResolvedValue(mockStats);
    render(<AlertScreen />);
    expect(await screen.findByText('Resolue')).toBeInTheDocument();
  });
});
