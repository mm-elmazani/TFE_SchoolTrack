import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, fireEvent, waitFor } from '../../../test/test-utils';
import { DeleteStudentDialog } from '../components/DeleteStudentDialog';
import { studentApi } from '../api/studentApi';

vi.mock('../api/studentApi', () => ({
  studentApi: { delete: vi.fn(), getAll: vi.fn() },
}));

const mockStudent = {
  id: 's1', first_name: 'Jean', last_name: 'Dupont', email: 'jean@test.be',
  class_name: '5ème A', created_at: '', updated_at: '',
} as any;

beforeEach(() => vi.clearAllMocks());

describe('DeleteStudentDialog', () => {
  it('renders dialog when open with student data', () => {
    render(<DeleteStudentDialog student={mockStudent} open={true} onOpenChange={vi.fn()} />);
    expect(screen.getByText(/Supprimer un .l.ve/i)).toBeInTheDocument();
  });

  it('shows student name in confirmation text', () => {
    render(<DeleteStudentDialog student={mockStudent} open={true} onOpenChange={vi.fn()} />);
    expect(screen.getByText(/Jean|Dupont/)).toBeInTheDocument();
  });

  it('renders delete and cancel buttons', () => {
    render(<DeleteStudentDialog student={mockStudent} open={true} onOpenChange={vi.fn()} />);
    expect(screen.getByRole('button', { name: /Supprimer/i })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /Annuler/i })).toBeInTheDocument();
  });

  it('closes when cancel is clicked', () => {
    const onOpenChange = vi.fn();
    render(<DeleteStudentDialog student={mockStudent} open={true} onOpenChange={onOpenChange} />);
    fireEvent.click(screen.getByRole('button', { name: /Annuler/i }));
    expect(onOpenChange).toHaveBeenCalledWith(false);
  });

  it('renders student full name in description', () => {
    render(<DeleteStudentDialog student={mockStudent} open={true} onOpenChange={vi.fn()} />);
    expect(screen.getByText(/Jean.*Dupont|Dupont.*Jean/)).toBeInTheDocument();
  });

  it('renders masquage information text', () => {
    render(<DeleteStudentDialog student={mockStudent} open={true} onOpenChange={vi.fn()} />);
    expect(screen.getByText(/masquera l.*l.ve/i)).toBeInTheDocument();
  });

  it('does not render when closed', () => {
    render(<DeleteStudentDialog student={mockStudent} open={false} onOpenChange={vi.fn()} />);
    expect(screen.queryByText(/Supprimer un .l.ve/i)).not.toBeInTheDocument();
  });
});
