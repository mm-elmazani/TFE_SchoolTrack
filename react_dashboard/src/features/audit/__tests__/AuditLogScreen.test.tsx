import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '../../../test/test-utils';
import AuditLogScreen from '../screens/AuditLogScreen';
import { auditApi } from '../api/auditApi';

// Mock API
vi.mock('../api/auditApi', () => ({
  auditApi: {
    getLogs: vi.fn(),
  },
}));

describe('AuditLogScreen', () => {
  it('renders loading state initially', () => {
    vi.mocked(auditApi.getLogs).mockReturnValue(new Promise(() => {}));
    render(<AuditLogScreen />);
    expect(screen.getByText('Chargement des logs...')).toBeInTheDocument();
  });

  it('renders a list of audit logs', async () => {
    const mockLogs = {
      items: [
        { 
          id: '1', 
          action: 'LOGIN_SUCCESS', 
          user_id: '1', 
          user_email: 'test@test.com',
          resource_type: 'AUTH', 
          resource_id: '1', 
          ip_address: '127.0.0.1', 
          user_agent: 'test', 
          details: {}, 
          performed_at: '2026-03-11T10:00:00Z' 
        },
      ],
      total: 1,
      page: 1,
      page_size: 20,
      total_pages: 1,
    };

    vi.mocked(auditApi.getLogs).mockResolvedValue(mockLogs);

    render(<AuditLogScreen />);
    
    expect(await screen.findByText("Journaux d'Audit")).toBeInTheDocument();
    expect(screen.getByText('test@test.com')).toBeInTheDocument();
  });
});
