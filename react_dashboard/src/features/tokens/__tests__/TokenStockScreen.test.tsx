import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, fireEvent } from '../../../test/test-utils';
import TokenStockScreen from '../screens/TokenStockScreen';
import { tokenApi } from '../api/tokenApi';
import { useAuthStore } from '@/features/auth/store/authStore';

vi.mock('../api/tokenApi', () => ({
  tokenApi: { getTokenStats: vi.fn(), getAllTokens: vi.fn(), updateTokenStatus: vi.fn(), deleteToken: vi.fn() },
}));

const mockStats = { total: 15, available: 8, assigned: 4, damaged: 2, lost: 1 };

const mockTokens = [
  {
    id: '1', token_uid: 'NFC-001', token_type: 'NFC_PHYSICAL', status: 'AVAILABLE',
    hardware_uid: 'HW-ABC', assigned_to: null, assigned_trip: null, created_at: '2026-01-15T10:00:00Z',
  },
  {
    id: '2', token_uid: 'QR-002', token_type: 'QR_PHYSICAL', status: 'ASSIGNED',
    hardware_uid: null, assigned_to: 'Jean Dupont', assigned_trip: 'Bruges', created_at: '2026-01-10T10:00:00Z',
  },
  {
    id: '3', token_uid: 'NFC-003', token_type: 'NFC_PHYSICAL', status: 'DAMAGED',
    hardware_uid: null, assigned_to: null, assigned_trip: null, created_at: '2026-01-05T10:00:00Z',
  },
];

beforeEach(() => {
  vi.clearAllMocks();
  useAuthStore.setState({
    token: 'test',
    user: { id: '1', email: 'admin@test.be', first_name: 'Admin', last_name: 'Test', role: 'DIRECTION' },
  });
});

describe('TokenStockScreen', () => {
  it('renders loading state', () => {
    vi.mocked(tokenApi.getTokenStats).mockReturnValue(new Promise(() => {}));
    vi.mocked(tokenApi.getAllTokens).mockReturnValue(new Promise(() => {}));
    render(<TokenStockScreen />);
    expect(screen.getByText(/Chargement du stock/i)).toBeInTheDocument();
  });

  it('renders empty token list', async () => {
    vi.mocked(tokenApi.getTokenStats).mockResolvedValue({ total: 0, available: 0, assigned: 0, damaged: 0, lost: 0 });
    vi.mocked(tokenApi.getAllTokens).mockResolvedValue([]);
    render(<TokenStockScreen />);
    expect(await screen.findByText(/Aucun bracelet/i)).toBeInTheDocument();
  });

  it('renders page title and subtitle', async () => {
    vi.mocked(tokenApi.getTokenStats).mockResolvedValue(mockStats);
    vi.mocked(tokenApi.getAllTokens).mockResolvedValue(mockTokens);
    render(<TokenStockScreen />);
    expect(await screen.findByText('Stock Bracelets')).toBeInTheDocument();
    expect(screen.getByText(/inventaire physique/i)).toBeInTheDocument();
  });

  it('renders stats cards with correct values', async () => {
    vi.mocked(tokenApi.getTokenStats).mockResolvedValue(mockStats);
    vi.mocked(tokenApi.getAllTokens).mockResolvedValue(mockTokens);
    render(<TokenStockScreen />);
    expect(await screen.findByText('15')).toBeInTheDocument();
    expect(screen.getByText('8')).toBeInTheDocument();
    expect(screen.getByText('4')).toBeInTheDocument();
    expect(screen.getByText('2')).toBeInTheDocument();
    expect(screen.getByText('1')).toBeInTheDocument();
    expect(screen.getAllByText('Disponibles').length).toBeGreaterThan(0);
    expect(screen.getAllByText(/Assign/i).length).toBeGreaterThan(0);
    expect(screen.getAllByText(/Endommag/i).length).toBeGreaterThan(0);
    expect(screen.getAllByText(/Perdus/i).length).toBeGreaterThan(0);
  });

  it('renders token table with data', async () => {
    vi.mocked(tokenApi.getTokenStats).mockResolvedValue(mockStats);
    vi.mocked(tokenApi.getAllTokens).mockResolvedValue(mockTokens);
    render(<TokenStockScreen />);
    expect(await screen.findByText('NFC-001')).toBeInTheDocument();
    expect(screen.getByText('QR-002')).toBeInTheDocument();
    expect(screen.getByText('NFC-003')).toBeInTheDocument();
  });

  it('renders status badges', async () => {
    vi.mocked(tokenApi.getTokenStats).mockResolvedValue(mockStats);
    vi.mocked(tokenApi.getAllTokens).mockResolvedValue(mockTokens);
    render(<TokenStockScreen />);
    await screen.findByText('NFC-001');
    expect(screen.getAllByText('Disponible').length).toBeGreaterThan(0);
    expect(screen.getAllByText(/Assign/i).length).toBeGreaterThan(0);
    expect(screen.getAllByText(/Endommag/i).length).toBeGreaterThan(0);
  });

  it('renders type badges', async () => {
    vi.mocked(tokenApi.getTokenStats).mockResolvedValue(mockStats);
    vi.mocked(tokenApi.getAllTokens).mockResolvedValue(mockTokens);
    render(<TokenStockScreen />);
    await screen.findByText('NFC-001');
    expect(screen.getAllByText('NFC Physique').length).toBeGreaterThan(0);
    expect(screen.getAllByText('QR Physique').length).toBeGreaterThan(0);
  });

  it('renders assigned-to info for assigned tokens', async () => {
    vi.mocked(tokenApi.getTokenStats).mockResolvedValue(mockStats);
    vi.mocked(tokenApi.getAllTokens).mockResolvedValue(mockTokens);
    render(<TokenStockScreen />);
    expect(await screen.findByText('Jean Dupont')).toBeInTheDocument();
    expect(screen.getByText('Bruges')).toBeInTheDocument();
  });

  it('renders hardware UID when present', async () => {
    vi.mocked(tokenApi.getTokenStats).mockResolvedValue(mockStats);
    vi.mocked(tokenApi.getAllTokens).mockResolvedValue(mockTokens);
    render(<TokenStockScreen />);
    expect(await screen.findByText(/HW: HW-ABC/)).toBeInTheDocument();
  });

  it('renders filter controls', async () => {
    vi.mocked(tokenApi.getTokenStats).mockResolvedValue(mockStats);
    vi.mocked(tokenApi.getAllTokens).mockResolvedValue(mockTokens);
    render(<TokenStockScreen />);
    await screen.findByText('NFC-001');
    expect(screen.getAllByText('Statut').length).toBeGreaterThan(0);
    expect(screen.getAllByText('Type').length).toBeGreaterThan(0);
    expect(screen.getByText(/Rafra/i)).toBeInTheDocument();
  });

  it('renders sortable table headers', async () => {
    vi.mocked(tokenApi.getTokenStats).mockResolvedValue(mockStats);
    vi.mocked(tokenApi.getAllTokens).mockResolvedValue(mockTokens);
    render(<TokenStockScreen />);
    await screen.findByText('NFC-001');
    expect(screen.getByText('Token UID')).toBeInTheDocument();
    expect(screen.getAllByText('Actions').length).toBeGreaterThan(0);
  });

  it('renders date column', async () => {
    vi.mocked(tokenApi.getTokenStats).mockResolvedValue(mockStats);
    vi.mocked(tokenApi.getAllTokens).mockResolvedValue(mockTokens);
    render(<TokenStockScreen />);
    await screen.findByText('NFC-001');
    expect(screen.getByText(/15\/01\/2026/)).toBeInTheDocument();
  });

  it('handles status filter change — re-fetches with new params', async () => {
    vi.mocked(tokenApi.getTokenStats).mockResolvedValue(mockStats);
    vi.mocked(tokenApi.getAllTokens).mockResolvedValue(mockTokens);
    render(<TokenStockScreen />);
    await screen.findByText('NFC-001');
    const selects = document.querySelectorAll('select');
    fireEvent.change(selects[0], { target: { value: 'AVAILABLE' } });
    // Re-fetch resolves with same mock — NFC-001 re-appears
    expect(await screen.findByText('NFC-001')).toBeInTheDocument();
  });

  it('handles type filter change — re-fetches with type param', async () => {
    vi.mocked(tokenApi.getTokenStats).mockResolvedValue(mockStats);
    vi.mocked(tokenApi.getAllTokens).mockResolvedValue(mockTokens);
    render(<TokenStockScreen />);
    await screen.findByText('NFC-001');
    const selects = document.querySelectorAll('select');
    fireEvent.change(selects[1], { target: { value: 'NFC_PHYSICAL' } });
    expect(await screen.findByText('NFC-001')).toBeInTheDocument();
  });

  it('handles sort by token UID column click', async () => {
    vi.mocked(tokenApi.getTokenStats).mockResolvedValue(mockStats);
    vi.mocked(tokenApi.getAllTokens).mockResolvedValue(mockTokens);
    render(<TokenStockScreen />);
    await screen.findByText('NFC-001');
    fireEvent.click(screen.getByText('Token UID'));
    expect(screen.getByText('NFC-001')).toBeInTheDocument();
  });

  it('handles sort by created_at column click', async () => {
    vi.mocked(tokenApi.getTokenStats).mockResolvedValue(mockStats);
    vi.mocked(tokenApi.getAllTokens).mockResolvedValue(mockTokens);
    render(<TokenStockScreen />);
    await screen.findByText('NFC-001');
    fireEvent.click(screen.getByText(/Cr.é le/));
    expect(screen.getByText('NFC-001')).toBeInTheDocument();
  });

  it('shows empty state when token list returns empty', async () => {
    vi.mocked(tokenApi.getTokenStats).mockResolvedValue({ total: 0, available: 0, assigned: 0, damaged: 0, lost: 0 });
    vi.mocked(tokenApi.getAllTokens).mockResolvedValue([]);
    render(<TokenStockScreen />);
    expect(await screen.findByText(/Aucun bracelet/i)).toBeInTheDocument();
  });
});
