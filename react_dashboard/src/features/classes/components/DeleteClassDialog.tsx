import { useState } from 'react';
import { useMutation, useQueryClient } from '@tanstack/react-query';
import { classApi, type Class } from '../api/classApi';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { AlertTriangle, Loader2 } from 'lucide-react';

interface DeleteClassDialogProps {
  cls: Class | null;
  open: boolean;
  onOpenChange: (open: boolean) => void;
}

export function DeleteClassDialog({ cls, open, onOpenChange }: DeleteClassDialogProps) {
  const [serverError, setServerError] = useState<string | null>(null);
  const queryClient = useQueryClient();

  const deleteMutation = useMutation({
    mutationFn: () => classApi.delete(cls!.id),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['classes'] });
      onOpenChange(false);
    },
    onError: (error: any) => {
      setServerError(error.response?.data?.detail || 'Erreur lors de la suppression');
    }
  });

  return (
    <Dialog open={open} onOpenChange={(val) => {
      setServerError(null);
      onOpenChange(val);
    }}>
      <DialogContent className="sm:max-w-[425px] rounded-2xl">
        <DialogHeader>
          <div className="w-12 h-12 bg-red-50 text-schooltrack-error rounded-full flex items-center justify-center mb-4">
            <AlertTriangle className="w-6 h-6" />
          </div>
          <DialogTitle className="text-2xl font-bold text-slate-900 font-heading">Supprimer la classe</DialogTitle>
          <DialogDescription className="text-slate-500">
            Êtes-vous sûr de vouloir supprimer la classe <span className="font-bold text-slate-900">{cls?.name}</span> ? Cette action est irréversible.
          </DialogDescription>
        </DialogHeader>

        {serverError && (
          <div className="p-3 bg-red-50 text-schooltrack-error border border-red-100 rounded-xl text-sm">
            {serverError}
          </div>
        )}

        <DialogFooter className="gap-3 pt-4">
          <Button 
            type="button" 
            variant="outline" 
            onClick={() => onOpenChange(false)}
            className="rounded-xl h-11 border-slate-200"
          >
            Annuler
          </Button>
          <Button 
            type="button" 
            variant="destructive"
            disabled={deleteMutation.isPending}
            onClick={() => deleteMutation.mutate()}
            className="rounded-xl h-11 bg-schooltrack-error hover:bg-red-700 text-white px-8 shadow-sm transition-all active:scale-95 border-0"
          >
            {deleteMutation.isPending ? (
              <>
                <Loader2 className="w-4 h-4 mr-2 animate-spin" />
                Suppression...
              </>
            ) : 'Supprimer définitivement'}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
