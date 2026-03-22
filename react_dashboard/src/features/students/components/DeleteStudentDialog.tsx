import { useState } from 'react';
import { useMutation, useQueryClient } from '@tanstack/react-query';
import { studentApi } from '../api/studentApi';
import type { Student } from '../api/studentApi';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';

interface DeleteStudentDialogProps {
  student: Student | null;
  open: boolean;
  onOpenChange: (open: boolean) => void;
}

export function DeleteStudentDialog({ student, open, onOpenChange }: DeleteStudentDialogProps) {
  const [error, setError] = useState<string | null>(null);
  const queryClient = useQueryClient();

  const deleteMutation = useMutation({
    mutationFn: studentApi.delete,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['students'] });
      onOpenChange(false);
    },
    onError: (err: any) => {
      setError(err.response?.data?.detail || 'Erreur lors de la suppression');
    }
  });

  const handleDelete = () => {
    if (student) {
      deleteMutation.mutate(student.id);
    }
  };

  return (
    <Dialog open={open} onOpenChange={(val) => {
      if (!val) setError(null);
      onOpenChange(val);
    }}>
      <DialogContent className="sm:max-w-[425px]">
        <DialogHeader>
          <DialogTitle>Supprimer un élève</DialogTitle>
          <DialogDescription>
            Êtes-vous sûr de vouloir supprimer {student?.first_name} {student?.last_name} ? 
            Cette action masquera l'élève du système.
          </DialogDescription>
        </DialogHeader>
        {error && (
          <div className="p-3 bg-red-100 text-red-700 rounded-md text-sm">
            {error}
          </div>
        )}
        <DialogFooter className="mt-4">
          <Button variant="outline" onClick={() => onOpenChange(false)} disabled={deleteMutation.isPending}>
            Annuler
          </Button>
          <Button variant="destructive" onClick={handleDelete} disabled={deleteMutation.isPending}>
            {deleteMutation.isPending ? 'Suppression...' : 'Supprimer'}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
