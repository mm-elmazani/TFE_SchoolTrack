import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, fireEvent, waitFor } from '../../../test/test-utils';
import { AssignTokenDialog } from '../components/AssignTokenDialog';
import { tokenApi } from '../api/tokenApi';

vi.mock('../api/tokenApi', () => ({
  tokenApi: {
    assignToken: vi.fn(),
    reassignToken: vi.fn(),
    getAllTokens: vi.fn(),
  },
}));

const mockStudent = {
  id: 's1', first_name: 'Jean', last_name: 'Dupont', is_assigned: false,
  assignment_id: null, token_uid: null, assignment_type: null, assigned_at: null,
  secondary_assignment_id: null, secondary_token_uid: null, secondary_assignment_type: null, secondary_assigned_at: null,
};

beforeEach(() => {
  vi.clearAllMocks();
  vi.mocked(tokenApi.getAllTokens).mockResolvedValue([
    { id: '1', token_uid: 'NFC-001', token_type: 'NFC_PHYSICAL', status: 'AVAILABLE', created_at: '' },
  ]);
});

describe('AssignTokenDialog', () => {
  it('renders assign dialog when open', () => {
    render(<AssignTokenDialog student={mockStudent} tripId="t1" open={true} onOpenChange={vi.fn()} />);
    expect(screen.getByText(/Assigner un bracelet/i)).toBeInTheDocument();
  });

  it('renders student name', () => {
    render(<AssignTokenDialog student={mockStudent} tripId="t1" open={true} onOpenChange={vi.fn()} />);
    expect(screen.getByText(/Jean.*Dupont|Dupont.*Jean/)).toBeInTheDocument();
  });

  it('renders type de support label', () => {
    render(<AssignTokenDialog student={mockStudent} tripId="t1" open={true} onOpenChange={vi.fn()} />);
    expect(screen.getByText(/Type de support/i)).toBeInTheDocument();
  });

  it('renders assign and cancel buttons', () => {
    render(<AssignTokenDialog student={mockStudent} tripId="t1" open={true} onOpenChange={vi.fn()} />);
    expect(screen.getByRole('button', { name: /Assigner/i })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /Annuler/i })).toBeInTheDocument();
  });

  it('renders reassign dialog when isReassign=true', () => {
    const assignedStudent = {
      ...mockStudent,
      is_assigned: true, assignment_id: 1, token_uid: 'NFC-001', assignment_type: 'NFC_PHYSICAL' as const, assigned_at: '2026-01-01',
    };
    render(<AssignTokenDialog student={assignedStudent} tripId="t1" open={true} onOpenChange={vi.fn()} isReassign={true} />);
    expect(screen.getByText(/Reassigner un bracelet/i)).toBeInTheDocument();
  });

  it('renders dialog title when forceDigital=true', () => {
    render(<AssignTokenDialog student={mockStudent} tripId="t1" open={true} onOpenChange={vi.fn()} forceDigital={true} />);
    expect(screen.getAllByText(/QR Digital|Ajouter un QR|Assigner/i).length).toBeGreaterThan(0);
  });

  it('renders UID du Token field', async () => {
    render(<AssignTokenDialog student={mockStudent} tripId="t1" open={true} onOpenChange={vi.fn()} />);
    expect(await screen.findByText(/UID du Token/i)).toBeInTheDocument();
  });

  it('shows available tokens in select when tokens loaded', async () => {
    render(<AssignTokenDialog student={mockStudent} tripId="t1" open={true} onOpenChange={vi.fn()} />);
    expect(await screen.findByText('NFC-001')).toBeInTheDocument();
  });

  it('shows input field when no physical tokens available', async () => {
    vi.mocked(tokenApi.getAllTokens).mockResolvedValue([]);
    render(<AssignTokenDialog student={mockStudent} tripId="t1" open={true} onOpenChange={vi.fn()} />);
    expect(await screen.findByPlaceholderText(/Scanner ou saisir/i)).toBeInTheDocument();
  });

  it('closes on cancel button click', () => {
    const onOpenChange = vi.fn();
    render(<AssignTokenDialog student={mockStudent} tripId="t1" open={true} onOpenChange={onOpenChange} />);
    fireEvent.click(screen.getByRole('button', { name: /Annuler/i }));
    expect(onOpenChange).toHaveBeenCalledWith(false);
  });

  it('shows justification field when isReassign=true', () => {
    const assignedStudent = {
      ...mockStudent,
      is_assigned: true, assignment_id: 1, token_uid: 'NFC-001', assignment_type: 'NFC_PHYSICAL' as const, assigned_at: '2026-01-01',
    };
    render(<AssignTokenDialog student={assignedStudent} tripId="t1" open={true} onOpenChange={vi.fn()} isReassign={true} />);
    expect(screen.getByText(/Justification/i)).toBeInTheDocument();
  });

  it('shows server error on assignment failure', async () => {
    vi.mocked(tokenApi.getAllTokens).mockResolvedValue([]);
    vi.mocked(tokenApi.assignToken).mockRejectedValue({
      response: { data: { detail: 'Token déjà assigné' } },
    });
    render(<AssignTokenDialog student={mockStudent} tripId="t1" open={true} onOpenChange={vi.fn()} />);
    const input = await screen.findByPlaceholderText(/Scanner ou saisir/i);
    fireEvent.change(input, { target: { value: 'NFC-TEST' } });
    fireEvent.click(screen.getByRole('button', { name: /Assigner/i }));
    expect(await screen.findByText('Token déjà assigné')).toBeInTheDocument();
  });

  it('does not render when closed', () => {
    render(<AssignTokenDialog student={mockStudent} tripId="t1" open={false} onOpenChange={vi.fn()} />);
    expect(screen.queryByText(/Assigner un bracelet/i)).not.toBeInTheDocument();
  });
});
