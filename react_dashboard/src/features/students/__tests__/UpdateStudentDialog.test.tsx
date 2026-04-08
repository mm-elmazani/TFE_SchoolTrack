import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, fireEvent, waitFor } from '../../../test/test-utils';
import { UpdateStudentDialog } from '../components/UpdateStudentDialog';
import { studentApi } from '../api/studentApi';

vi.mock('../api/studentApi', () => ({
  studentApi: { update: vi.fn(), uploadPhoto: vi.fn(), getPhotoBlobUrl: vi.fn() },
}));

const mockStudent = {
  id: 's1', first_name: 'Jean', last_name: 'Dupont', email: 'jean@test.be',
  class_name: '5ème A', created_at: '', updated_at: '',
} as any;

beforeEach(() => vi.clearAllMocks());

describe('UpdateStudentDialog', () => {
  it('renders dialog when open with student data', () => {
    render(<UpdateStudentDialog student={mockStudent} open={true} onOpenChange={vi.fn()} />);
    expect(screen.getByText(/Modifier l.*l.ve/i)).toBeInTheDocument();
  });

  it('pre-fills first name', () => {
    render(<UpdateStudentDialog student={mockStudent} open={true} onOpenChange={vi.fn()} />);
    expect(screen.getByDisplayValue('Jean')).toBeInTheDocument();
  });

  it('pre-fills last name', () => {
    render(<UpdateStudentDialog student={mockStudent} open={true} onOpenChange={vi.fn()} />);
    expect(screen.getByDisplayValue('Dupont')).toBeInTheDocument();
  });

  it('pre-fills email', () => {
    render(<UpdateStudentDialog student={mockStudent} open={true} onOpenChange={vi.fn()} />);
    expect(screen.getByDisplayValue('jean@test.be')).toBeInTheDocument();
  });

  it('renders form labels', () => {
    render(<UpdateStudentDialog student={mockStudent} open={true} onOpenChange={vi.fn()} />);
    expect(screen.getByText('Nom')).toBeInTheDocument();
    expect(screen.getByText(/Pr.nom/i)).toBeInTheDocument();
    expect(screen.getByText(/Email/i)).toBeInTheDocument();
  });

  it('renders save and cancel buttons', () => {
    render(<UpdateStudentDialog student={mockStudent} open={true} onOpenChange={vi.fn()} />);
    expect(screen.getByRole('button', { name: /sauvegarder/i })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /annuler/i })).toBeInTheDocument();
  });

  it('renders photo section', () => {
    render(<UpdateStudentDialog student={mockStudent} open={true} onOpenChange={vi.fn()} />);
    expect(screen.getByText(/Photo/i)).toBeInTheDocument();
  });

  it('renders dialog subtitle', () => {
    render(<UpdateStudentDialog student={mockStudent} open={true} onOpenChange={vi.fn()} />);
    expect(screen.getByText(/Modifiez les informations/i)).toBeInTheDocument();
  });

  it('calls studentApi.update on submit', async () => {
    vi.mocked(studentApi.update).mockResolvedValue({ id: 's1' } as any);
    render(<UpdateStudentDialog student={mockStudent} open={true} onOpenChange={vi.fn()} />);
    fireEvent.click(screen.getByRole('button', { name: /sauvegarder/i }));
    await waitFor(() => expect(studentApi.update).toHaveBeenCalled());
  });

  it('shows server error on update failure', async () => {
    vi.mocked(studentApi.update).mockRejectedValue({
      response: { data: { detail: 'Email déjà utilisé' } },
    });
    render(<UpdateStudentDialog student={mockStudent} open={true} onOpenChange={vi.fn()} />);
    fireEvent.click(screen.getByRole('button', { name: /sauvegarder/i }));
    expect(await screen.findByText('Email déjà utilisé')).toBeInTheDocument();
  });

  it('closes on cancel', () => {
    const onOpenChange = vi.fn();
    render(<UpdateStudentDialog student={mockStudent} open={true} onOpenChange={onOpenChange} />);
    fireEvent.click(screen.getByRole('button', { name: /annuler/i }));
    expect(onOpenChange).toHaveBeenCalledWith(false);
  });
});
