import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, fireEvent, waitFor } from '../../../test/test-utils';
import { ArchiveTripDialog } from '../components/ArchiveTripDialog';
import { tripApi } from '../api/tripApi';

vi.mock('../api/tripApi', () => ({
  tripApi: { archive: vi.fn() },
}));

const mockTrip = {
  id: 't1', destination: 'Paris', date: '2026-05-10', description: 'Test', status: 'ACTIVE',
  total_students: 25, classes: [], created_at: '', updated_at: '',
} as any;

beforeEach(() => vi.clearAllMocks());

describe('ArchiveTripDialog', () => {
  it('renders dialog when open with trip', () => {
    render(<ArchiveTripDialog trip={mockTrip} open={true} onOpenChange={vi.fn()} />);
    expect(screen.getByText('Archiver le voyage')).toBeInTheDocument();
    expect(screen.getByText(/Paris/)).toBeInTheDocument();
  });

  it('renders archive and cancel buttons', () => {
    render(<ArchiveTripDialog trip={mockTrip} open={true} onOpenChange={vi.fn()} />);
    expect(screen.getByRole('button', { name: /Archiver/i })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /Annuler/i })).toBeInTheDocument();
  });

  it('renders conservation warning in description', () => {
    render(<ArchiveTripDialog trip={mockTrip} open={true} onOpenChange={vi.fn()} />);
    expect(screen.getByText(/donn.es seront conserv.es/i)).toBeInTheDocument();
  });

  it('closes when cancel is clicked', () => {
    const onOpenChange = vi.fn();
    render(<ArchiveTripDialog trip={mockTrip} open={true} onOpenChange={onOpenChange} />);
    fireEvent.click(screen.getByRole('button', { name: /Annuler/i }));
    expect(onOpenChange).toHaveBeenCalledWith(false);
  });

  it('renders destructive archive button (variant=destructive)', () => {
    render(<ArchiveTripDialog trip={mockTrip} open={true} onOpenChange={vi.fn()} />);
    const allButtons = screen.getAllByRole('button');
    const archiveBtn = allButtons.find(b => b.className.includes('destructive'));
    expect(archiveBtn).toBeTruthy();
    expect((archiveBtn?.textContent || '').trim()).toMatch(/Archiver/);
  });

  it('renders trip destination in description', () => {
    render(<ArchiveTripDialog trip={mockTrip} open={true} onOpenChange={vi.fn()} />);
    expect(screen.getAllByText(/Paris/).length).toBeGreaterThan(0);
  });

  it('renders dialog footer with two action buttons', () => {
    render(<ArchiveTripDialog trip={mockTrip} open={true} onOpenChange={vi.fn()} />);
    const buttons = screen.getAllByRole('button');
    const footerButtons = buttons.filter(b => b.textContent?.match(/Archiver|Annuler/));
    expect(footerButtons.length).toBeGreaterThanOrEqual(2);
  });

  it('does not render when closed', () => {
    render(<ArchiveTripDialog trip={mockTrip} open={false} onOpenChange={vi.fn()} />);
    expect(screen.queryByText('Archiver le voyage')).not.toBeInTheDocument();
  });
});
