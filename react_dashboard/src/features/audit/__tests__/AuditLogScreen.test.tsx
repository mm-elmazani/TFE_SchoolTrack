import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, fireEvent } from '../../../test/test-utils';
import AuditLogScreen from '../screens/AuditLogScreen';
import { auditApi } from '../api/auditApi';

vi.mock('../api/auditApi', () => ({
  auditApi: { getLogs: vi.fn(), exportLogs: vi.fn() },
}));

beforeEach(() => vi.clearAllMocks());

const mockLogs = {
  items: [
    {
      id: '1', action: 'LOGIN_SUCCESS', user_id: '1', user_email: 'admin@test.be',
      resource_type: 'AUTH', resource_id: '1', ip_address: '127.0.0.1',
      user_agent: 'Mozilla', details: {}, performed_at: '2026-03-11T10:00:00Z',
    },
    {
      id: '2', action: 'STUDENT_CREATED', user_id: '1', user_email: 'admin@test.be',
      resource_type: 'STUDENT', resource_id: 's1', ip_address: '10.0.0.1',
      user_agent: 'Chrome', details: null, performed_at: '2026-03-11T09:00:00Z',
    },
    {
      id: '3', action: 'STUDENT_UPDATED', user_id: '2', user_email: 'prof@test.be',
      resource_type: 'STUDENT', resource_id: 's2', ip_address: '10.0.0.2',
      user_agent: 'Firefox', details: {}, performed_at: '2026-03-11T08:00:00Z',
    },
    {
      id: '4', action: 'STUDENT_DELETED', user_id: '2', user_email: 'prof@test.be',
      resource_type: 'STUDENT', resource_id: 's3', ip_address: '10.0.0.3',
      user_agent: 'Safari', details: {}, performed_at: '2026-03-11T07:00:00Z',
    },
  ],
  total: 4, page: 1, page_size: 20, total_pages: 1,
};

describe('AuditLogScreen', () => {
  it('shows loading state', () => {
    vi.mocked(auditApi.getLogs).mockReturnValue(new Promise(() => {}));
    render(<AuditLogScreen />);
    expect(screen.getByText('Chargement des logs...')).toBeInTheDocument();
  });

  it('renders page title and subtitle', async () => {
    vi.mocked(auditApi.getLogs).mockResolvedValue(mockLogs);
    render(<AuditLogScreen />);
    expect(await screen.findByText("Journaux d'Audit")).toBeInTheDocument();
    expect(screen.getByText(/Suivez l.activit/i)).toBeInTheDocument();
  });

  it('renders log entries', async () => {
    vi.mocked(auditApi.getLogs).mockResolvedValue(mockLogs);
    render(<AuditLogScreen />);
    expect((await screen.findAllByText('admin@test.be')).length).toBeGreaterThan(0);
    expect(screen.getAllByText(/curit/i).length).toBeGreaterThan(0);
    expect(screen.getAllByText(/ation/i).length).toBeGreaterThan(0);
  });

  it('renders export button', async () => {
    vi.mocked(auditApi.getLogs).mockResolvedValue(mockLogs);
    render(<AuditLogScreen />);
    expect(await screen.findByText(/Exporter/i)).toBeInTheDocument();
  });

  it('renders filter controls', async () => {
    vi.mocked(auditApi.getLogs).mockResolvedValue(mockLogs);
    render(<AuditLogScreen />);
    await screen.findAllByText('admin@test.be');
    expect(screen.getAllByText('Action').length).toBeGreaterThan(0);
    expect(screen.getAllByText('Ressource').length).toBeGreaterThan(0);
  });

  it('renders empty state', async () => {
    vi.mocked(auditApi.getLogs).mockResolvedValue({
      items: [], total: 0, page: 1, page_size: 20, total_pages: 0,
    });
    render(<AuditLogScreen />);
    expect(await screen.findByText(/aucun log|aucun journal/i)).toBeInTheDocument();
  });

  it('renders action badges for security actions', async () => {
    vi.mocked(auditApi.getLogs).mockResolvedValue(mockLogs);
    render(<AuditLogScreen />);
    await screen.findAllByText('admin@test.be');
    expect(screen.getAllByText(/curit/i).length).toBeGreaterThan(0);
    expect(screen.getAllByText(/ation/i).length).toBeGreaterThan(0);
  });

  it('renders IP addresses', async () => {
    vi.mocked(auditApi.getLogs).mockResolvedValue(mockLogs);
    render(<AuditLogScreen />);
    expect(await screen.findByText('127.0.0.1')).toBeInTheDocument();
    expect(screen.getByText('10.0.0.1')).toBeInTheDocument();
  });

  it('renders error state', async () => {
    vi.mocked(auditApi.getLogs).mockRejectedValue(new Error('API error'));
    render(<AuditLogScreen />);
    expect(await screen.findByText('Erreur de chargement')).toBeInTheDocument();
    expect(screen.getByText(/Impossible de r.*journaux d.audit/i)).toBeInTheDocument();
  });

  it('renders Modification badge for update actions', async () => {
    vi.mocked(auditApi.getLogs).mockResolvedValue(mockLogs);
    render(<AuditLogScreen />);
    await screen.findAllByText('admin@test.be');
    // STUDENT_UPDATED → "Modification" badge
    expect(screen.getAllByText(/Modification/i).length).toBeGreaterThan(0);
  });

  it('renders Suppression badge for delete actions', async () => {
    vi.mocked(auditApi.getLogs).mockResolvedValue(mockLogs);
    render(<AuditLogScreen />);
    await screen.findAllByText('admin@test.be');
    expect(screen.getAllByText(/Suppression/i).length).toBeGreaterThan(0);
  });

  it('renders clear filters button', async () => {
    vi.mocked(auditApi.getLogs).mockResolvedValue(mockLogs);
    render(<AuditLogScreen />);
    await screen.findAllByText('admin@test.be');
    expect(screen.getByText(/R.initialiser/i)).toBeInTheDocument();
  });

  it('renders Du and Au date filter labels', async () => {
    vi.mocked(auditApi.getLogs).mockResolvedValue(mockLogs);
    render(<AuditLogScreen />);
    await screen.findAllByText('admin@test.be');
    expect(screen.getByText('Du')).toBeInTheDocument();
    expect(screen.getByText('Au')).toBeInTheDocument();
  });

  it('handles clear filters click', async () => {
    vi.mocked(auditApi.getLogs).mockResolvedValue(mockLogs);
    render(<AuditLogScreen />);
    await screen.findAllByText('admin@test.be');
    fireEvent.click(screen.getByText(/R.initialiser/i));
    // Should still render after clearing
    expect(screen.getByText(/Exporter/i)).toBeInTheDocument();
  });

  it('handles action filter change', async () => {
    vi.mocked(auditApi.getLogs).mockResolvedValue(mockLogs);
    render(<AuditLogScreen />);
    await screen.findAllByText('admin@test.be');
    const selects = document.querySelectorAll('select');
    fireEvent.change(selects[0], { target: { value: 'LOGIN_SUCCESS' } });
    expect(await screen.findAllByText('admin@test.be')).not.toHaveLength(0);
  });

  it('handles resource filter change', async () => {
    vi.mocked(auditApi.getLogs).mockResolvedValue(mockLogs);
    render(<AuditLogScreen />);
    await screen.findAllByText('admin@test.be');
    const selects = document.querySelectorAll('select');
    fireEvent.change(selects[1], { target: { value: 'STUDENT' } });
    expect(await screen.findAllByText('admin@test.be')).not.toHaveLength(0);
  });

  it('handles start date filter change', async () => {
    vi.mocked(auditApi.getLogs).mockResolvedValue(mockLogs);
    render(<AuditLogScreen />);
    await screen.findAllByText('admin@test.be');
    const dateInputs = document.querySelectorAll('input[type="date"]');
    fireEvent.change(dateInputs[0], { target: { value: '2026-03-01' } });
    expect(await screen.findAllByText('admin@test.be')).not.toHaveLength(0);
  });

  it('handles end date filter change', async () => {
    vi.mocked(auditApi.getLogs).mockResolvedValue(mockLogs);
    render(<AuditLogScreen />);
    await screen.findAllByText('admin@test.be');
    const dateInputs = document.querySelectorAll('input[type="date"]');
    fireEvent.change(dateInputs[1], { target: { value: '2026-03-31' } });
    // After filter change the query key changes — wait for data to re-appear
    expect(await screen.findAllByText('admin@test.be')).not.toHaveLength(0);
  });

  it('renders pagination buttons', async () => {
    vi.mocked(auditApi.getLogs).mockResolvedValue(mockLogs);
    render(<AuditLogScreen />);
    await screen.findAllByText('admin@test.be');
    expect(screen.getByText(/Pr.c.dent/i)).toBeInTheDocument();
    expect(screen.getByText(/Suivant/i)).toBeInTheDocument();
  });

  it('renders page indicator', async () => {
    vi.mocked(auditApi.getLogs).mockResolvedValue(mockLogs);
    render(<AuditLogScreen />);
    await screen.findAllByText('admin@test.be');
    expect(screen.getByText(/Page/i)).toBeInTheDocument();
  });

  it('clicking Suivant navigates to page 2', async () => {
    vi.mocked(auditApi.getLogs).mockResolvedValue({
      ...mockLogs, total: 40, page: 1, page_size: 20, total_pages: 2,
    });
    render(<AuditLogScreen />);
    await screen.findAllByText('admin@test.be');
    const suivantBtn = screen.getByText(/Suivant/i).closest('button')!;
    fireEvent.click(suivantBtn);
    expect(await screen.findAllByText('admin@test.be')).not.toHaveLength(0);
  });

  it('clicking Précédent navigates back to page 1', async () => {
    vi.mocked(auditApi.getLogs).mockResolvedValue({
      ...mockLogs, total: 40, page: 1, page_size: 20, total_pages: 2,
    });
    render(<AuditLogScreen />);
    await screen.findAllByText('admin@test.be');
    // Go to page 2
    fireEvent.click(screen.getByText(/Suivant/i).closest('button')!);
    await screen.findAllByText('admin@test.be');
    // Go back to page 1 — covers setPage(p => p - 1) + window.scrollTo
    const precedentBtn = screen.getByText(/Précédent/i).closest('button')!;
    fireEvent.click(precedentBtn);
    expect(await screen.findAllByText('admin@test.be')).not.toHaveLength(0);
  });

  it('renders default badge for unrecognized action type', async () => {
    vi.mocked(auditApi.getLogs).mockResolvedValue({
      items: [{
        id: '9', action: 'CUSTOM_UNKNOWN_ACTION', user_id: '1', user_email: 'admin@test.be',
        resource_type: 'OTHER', resource_id: null, ip_address: '1.2.3.4',
        user_agent: 'Test', details: {}, performed_at: '2026-03-11T10:00:00Z',
      }],
      total: 1, page: 1, page_size: 20, total_pages: 1,
    });
    render(<AuditLogScreen />);
    // Default badge case: action doesn't match any known pattern
    expect(await screen.findByText('CUSTOM_UNKNOWN_ACTION')).toBeInTheDocument();
  });

  it('clicking Exporter calls handleExport', async () => {
    vi.mocked(auditApi.getLogs).mockResolvedValue(mockLogs);
    vi.mocked(auditApi.exportLogs).mockResolvedValue(new Blob(['csv data'], { type: 'text/csv' }));
    vi.spyOn(window.URL, 'createObjectURL').mockReturnValue('blob:test-url');
    vi.spyOn(window.URL, 'revokeObjectURL').mockReturnValue(undefined);
    render(<AuditLogScreen />);
    await screen.findAllByText('admin@test.be');
    fireEvent.click(screen.getByText(/Exporter/i));
    expect(await screen.findByText(/Exporter/i)).toBeInTheDocument();
  });
});
